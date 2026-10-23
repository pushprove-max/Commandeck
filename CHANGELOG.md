# Changelog

## 0.39.0 -- 2026-10-23

- A review finding now blocks the merge only when normal use would hit the bug (owner ruling of 2026-10-23, over
  0.29.0's every-finding rule). A finding that needs an agent deliberately bypassing a guard, or an odd setup, is a
  one-line known gap in the evidence file and does not block. The reviewer prompt in `builder-codex-pass.sh` asks for
  such findings under a `KNOWN GAPS:` line with no level and no class tag, and a pass with only known gaps ends GO;
  a GO beside a tagged finding is still a NO-GO. The global rules, the Builder brief template and `docs/review-loop.md`
  state the same rule. Fixes #325.

## 0.38.0 -- 2026-10-23

- Launched Codex panes no longer wait on Codex's "Update available" prompt. Setup writes `check_for_update_on_startup
  = false` into the Codex home's `config.toml` (kept if the owner set the key; shown in the `--plan` preview; uninstall
  takes the line out). Setup, `update.sh` and `doctor.sh` run `codex update` when a newer Codex is out and say so; a
  failed or hung update (stopped after 300 s) is reported loudly, under "Needs you" in setup, and the run goes on with
  the current version. A pane that still opens on the prompt is answered Skip within a bound and the answer is logged;
  one that stays on it ends its launch `phase=failed`, naming it. `doctor.sh` reports the update check and the
  installed and latest versions. Fixes #314.

## 0.36.0 -- 2026-10-23

- Every seat can read GitHub, and a seat that cannot is not launched (issue 316). The cause was measured: the Codex
  read-only sandbox has no network, while `gh`'s sign-in is visible in every sandbox. The plan judges (Sol, Astra) now
  run Codex's read-only permission profile with network on, so files stay read-only and `gh` reaches GitHub. The plan
  judges run with network on and your `gh` sign-in, so they can write to GitHub and reach any host; the owner accepted
  that, and every guard still runs in their panes.
- Before a seat opens, `seat.sh launch` makes one `gh repo view` the way that seat would (its sandbox, Codex home,
  `shellEnv` and settings env, against its target repo) and refuses with the reason: no network in the sandbox, no
  credentials visible in the sandbox, not signed in to gh, or no GitHub remote. Main's restart makes the same read
  and, when it fails, leaves the old pane up.
- The review pass makes its read before any reviewer starts, with or without a `Closes:` line. The Claude reviewer
  gets `gh issue view`, `gh pr view` and `gh pr checks`; the Codex reviewer, whose sandbox the Codex plugin fixes
  without network, is handed the live `Closes:` issues whole (body and comments), every issue or pull request they
  link (the links GitHub itself renders in them) and the pull request state, read on the host with the reviewer's `shellEnv`. A reviewer reply that ends on a
  `BLOCKED: GitHub read failed:` line refuses the pass, and that round can run again; the line anywhere else in a
  reply makes it a NO-GO.
- A seat that loses GitHub mid-task prints `BLOCKED: GitHub read failed: <command>: <first error line>`, which wakes
  main like a `QUESTION:` line. `doctor.sh` reports GitHub read per agent, sandbox mode and seat environment.

## 0.35.0 -- 2026-10-23

- A running detached merge is visible, guarded and not duplicated (issue 317). `merge-unit-local.sh` writes
  `merge-unit-local.state` (unit, reviewed sha, pid, start, stage, log) beside its lock in main's git dir while it holds
  main, and removes it on every way out; a pid that is dead is a stale lock and blocks nothing. From main's foreground
  it prints `running detached as pid N; watch <log>`.
- A new hook, `merge-lock-guard.sh`, refuses `git stash`, `checkout`, `reset`, `clean` (and the other commands that move
  main's tree or index) and edits of files in main's checkout while that lock is live, naming the running merge. Each git
  call is judged on the checkout it changes: its `cd`'s, `-C`, `--git-dir` and `--work-tree`, `/usr/bin/git`, and the
  string a `bash -c` or `eval` runs; from main, a command on a Builder's worktree is that worktree's.
- The guard checks a redirection's or an edit's whole file, links followed, and main's `rg` takes only options that read.
  A file git is given to write is checked the same way: `GIT_INDEX_FILE`, `GIT_CONFIG*`, a `GIT_TRACE*` path, and the
  arguments of a git call that writes (`--output=`, `-o<file>`, `--prefix=`, `worktree add <path>`); `GIT_COMMON_DIR`
  and `GIT_OBJECT_DIRECTORY` are read as folders, like `GIT_DIR`. Such an argument built from data (a `$` value, quoted
  prose, a glob) or a link the same line makes is not seen.
  While the lock is live, a command in main's checkout may hold no `$` and no backtick, and `printf` takes no `-v` (bash
  runs a `$( )` held in a string it evaluates as a subscript or arithmetic, quoted or not). `orca-ide terminal send`
  from main is not seen (an accepted gap), nor is a program git's config names (`diff.external`, a textconv or filter
  driver, `core.fsmonitor`, a pager, gpg's program), which a git read runs like a script file. Outside main's checkout
  the guard screens the git calls a command types; code the command builds from data (a `$( )` in a here-document's
  body, text fed to a shell or an interpreter, a command word made by an expansion) is not seen either. Nor, in main's
  checkout too, is script text fed to `bash` or `sh` (`/dev/stdin`, `/dev/fd`, a `/proc` fd, a fifo) in place of a
  script file (an accepted gap).
- A request to merge a unit at a commit that is already running or waiting on the lock is a no-op that says so (exit 4),
  on the hand path and in main-watch's automatic merge. From main's foreground the request is queued before it detaches,
  so a duplicate is refused at once and never starts a run that would empty the running merge's log; `merge-queue.sh`
  appends to a unit's log, so a duplicate leaves the running merge's steps in place. The "staged work changed during the
  run" refusal stays hard, now tested, and its text names a changed index as a cause.
- `AGENT_STARTUP.md` and the first-build guide tell the orchestrator that the merge detaches, how to wait on it (its log
  or the message it sends), and never to re-run it.

## 0.34.0 -- 2026-10-23

- Codex panes no longer sit on the "hooks need review" menu when another tool's hook changed. Setup asks once, with
  the saved answer first, "Trust every hook in this Codex home before each Codex launch?" (`--trust-all-hooks
  on|off`, saved as `trustAllHooks`; the `--plan` preview lists the hooks it would trust). With yes, every seat launch
  and every review pass trusts every hook in the Codex home again right before Codex starts (`codex-hook-trust.py
  --all`); with no, only the plugin's own hooks are trusted, as before, and a pane that still opens on the review menu
  ends its launch `phase=failed` within the tui-idle wait, naming the hooks and the fix. `doctor.sh` now checks every
  hook in the Codex home and names the ones not trusted or modified. Fixes #315.

## 0.33.0 -- 2026-10-23

- Setup's own preview and apply pass the dependency guard again (issue 311): the plugin's `setup.sh` is recognised in
  any one version folder of the plugin cache, so a hook from one plugin version no longer blocks the `setup.sh` of
  another. A here-document body that only mentions install commands is no longer blocked beside a `cd` or `mkdir`;
  a body is skipped only on a line of one fixed shape (`cd`/`mkdir -p` steps, then a sender writing it out), so a body
  that a shell, a group, a pipe or a quoted argument could run is still read as code.
- Every one-line question in setup offers 2 to 4 options, so the question tool no longer drops "Worker cuts", "Keep
  words", "Merge check" or "Relay voice"; a failed question call is named with its error, never answered as "None".
- The Builder handoff line accepts `140k`, `140K` and `140000`.

## 0.32.0 -- 2026-10-22

- The global rules now carry the reviewer rules (one full scope for every reviewer; a finding names file, line and the
  failing input, and a P0-P2 finding a failing test; read the diff and brief before the evidence), no `ponytail` tag in
  comments, one unit per worktree split by code area, stop and reconcile on an unknown worktree, commit or process,
  no duplicate agent, and the planning rules (freshness pass, integration surface and siblings, review questions
  before code, evidence as you go, the anti-over-engineering gate, acceptance names the test file and cases).
- The Codex and Claude review prompt tells the reviewer to read cold, keep to the diff and its callers, attach a
  failing test to a P0-P2 finding, and follow the brief over the startup file. Each of a first pass's three
  reviewers leads with its own angle and is handed all three, so no angle rests on one reviewer.
- The Builder brief template maps the code with 3-4 read-only helpers before the first edit and gives an editing
  helper its own child worktree. `AGENT_STARTUP.md` adds: own your scope, fix every copy of a bug pattern, never work
  round a refusing check, confirm an irreversible action.
- A `Closes: #n` line in the batch brief is carried into the merge commit as `Closes #n`, and the merge closes the
  issue. The merge closes only the unit's work items: the list `builder-launch.sh` prints in its dry run and writes at
  launch to main's checkout (`.claude/briefs/<unit>-issues.json`), never a parse of the brief at merge time. Any other
  issue brief text names to close (a quoted example included, however it is quoted), and every issue of a unit
  launched without that list, is printed as a by-hand `gh issue close` under NOT CLOSED, and the merge ends with code 3.

## 0.31.0 -- 2026-10-22

- Main's shell suite is green again after the 320/321b, 322 and 323 merges met: three tests fixed, no product change.
  One test built its fixture with a jq form that jq 1.7.1 (CI's) refuses; one counted the new `planref=` record line as
  a plan; one hook comment read as a bare BLOCKED text.

## 0.30.0 -- 2026-10-22

- A plan seat that reported its finish in its own message to the run or main ("Plan revised", a `PLAN-DONE` line),
  or committed a new plan since its latest prompt, is finished, not "stuck" or "stopped": main-watch, `seat.sh wait`
  and collect all read it, and collect closes the pane (#320). A report quoted in a fence or under a `QUESTION:` or
  `BLOCKED:` line, one from before main's follow-up, or one while the turn still runs is not a finish, and it stands
  in for `PLAN-DONE` only, never a verdict. When the plan is committed and the turn ended without `PLAN-DONE`, the
  Claude seat's Stop hook asks for the line once.
- A seat pane's turn end (a Builder's own Codex pass included) sends main no "turn complete" echo, and collect sends a
  finish only when a wait claimed it and the seat did not report it itself (#321).
- A `QUESTION:` or `BLOCKED:` line at a turn's end always reaches main, once. A seat that stops silently is still
  caught by main-watch's and `seat.sh wait`'s own timers, and their alert now shows the pane's last words (#321).
- main-watch, `to-main.sh` and `cos-tell.sh --note` always send with a sender (main's pane, else the run's live
  coordinator): Orca refused main-watch's every task and message when it listed main's pane with no agent (#321).
- A message from the relay's pane (any pane in the Chief-of-Staff worktree) always wakes main and prints among the
  wake's own lines, whatever its type, with or without a ruling id, and whatever `wakeKinds` says (#324).

## 0.29.0 -- 2026-10-22

- Every review finding, P0 to P3, blocks the merge and is fixed in the unit (#322). The P2 tail is gone: no
  narrowed-pass acceptance, no "Open at merge:" lines, no issues filed at merge. A finding main cleared is handed to
  the reviewer as out of scope; it never turns a NO-GO into a merge. A reviewer's GO that names any finding is a
  NO-GO, and after any closing NO-GO the next `review` runs as the closing pass.
- One finding rule for every reader: the merge gate, the hand-on to the next reviewer, the tests per finding and the
  repeat-class stop all count a line with a P0-P3 level in any form, or a `(class:` tag with no level.
- `merge-unit-local.sh` drops `--area`, `--milestone` and exit code 4, and `merge-queue.sh` no longer goes on past
  an exit 4. `file-open-findings.sh` is removed.
- The dashboard no longer shows findings open at a merge: a finished build has no "Open at merge" line or amber
  Merge step, and the needs card no longer counts open P1s on finished builds.

## 0.28.0 -- 2026-10-22

- Red proofs are retired (#323). The Builder brief template no longer orders them, `scripts/red-proof.sh` is gone,
  and a fix-round hand-off names each finding's test and run command only. A pass no longer refuses a new guard test
  for a missing `Mutation-verified:` line and puts none in its commit; the merge no longer carries one into the
  squash message, and a branch that still has one merges.
- The Builder brief, batch brief and global rules follow the owner's current workflow: every review finding, P0 to
  P3, blocks the merge, and Done is a closing GO that names no finding. New rules: send main a question and keep
  working on what it cannot change; a finding against an owner ruling goes to main; read the inbox with `--ack`;
  never overlap the closing run with a long run; one test per bug class; a test only for a real regression; name
  what a new flow step catches; comments carry no credits or P-levels; main may raise a Builder's effort, never
  lower it.
- New default seats: a Builder runs Sonnet high (was Opus medium), every fix round Opus high (the first one kept the
  Builder's launch; `fixerFirstModel=builder` and `fixerFirstEffort=builder` still do), and main runs at medium
  effort, which setup now writes to main's settings file when `orchestratorEffort` is unset. A project's own
  `routing.json` keeps its seats; setup's questions recommend the new defaults.

## 0.27.0 -- 2026-10-22

- Only actionable messages wake main (#318). A nudge whose unread mail is all status notes or heartbeats is dropped
  with no turn spent; the notes show under "held notes (did not wake you)" at the next real wake, main's own notes
  included. Actionable messages that arrive within one window wake main once, counted across Orca's nudges and
  main-watch's typed wakes. Each wake that passes carries a silent-wake line: a wake with nothing for the owner ends
  with no text to them.
- Two new `/plugin` options: `wakeKinds` (default `worker_done,escalation,question,decision_gate,merge_ready`) and
  `wakeWindowSeconds` (default 60; 0 wakes at once).
- A merge main-watch lands now tells main once (`main-watch: <unit> merged into local main at <sha>`). A detached
  merge's or suite's exit notice is a question, and a heads-up relay is a status note.

## 0.26.0 -- 2026-10-22

- Seven roles are left: orchestrator, plan-author, plan-judge-sol, plan-judge-astra, builder, fixer and
  codex-reviewer. The second plan author, the Claude judge, the Claude reviewer, the design co-author, the platform
  audit and the three plugin agent files are gone. A Panel is one plan author and both judges. A `--risky` launch
  opens the Builder at once and its merge waits on three reviewers.
- Helpers are the built-in types: `Explore` runs on Haiku and `general-purpose` on Sonnet. The model guard asks for
  a type when a call names none.
- The new fixer role runs the fix passes after a review: the first one on the model and effort the Builder was
  launched with, the later ones on Opus high. The `fixer*` keys change both; `fixerEnabled=false` keeps every fix
  pass on the Builder's launch (#313).
- Each role's model, effort, agent, on/off and fast tier is a `/plugin` config key, 25 new keys, read by one checked
  reader; a value a role does not take is refused, naming the key. The reviewer and both judges can run on Claude by
  their agent key. Setup takes `--option <key>=<value>` in place of `--builder-model`, `--builder-effort`,
  `--codex-model`, `--plan-models`, `--plan-fast` and `--codex-fast`, and writes the main session's model and effort.
  Role settings an older setup saved in `.claude/commandeck.json` are no longer read: set them again as keys (#312).

## 0.25.3 -- 2026-10-22

- Fifteen plugin test cases that another named case already proves are gone, so the suites run fewer duplicate
  checks.
- The platform audit's "no duplicate answer" case now fails when the verifier stops requiring the duplicate cell;
  before, it passed with that rule removed.

## 0.25.2 -- 2026-10-22

- The fresh-session pass test no longer fails on a fast CI runner: its long-pass case sets the threshold below zero,
  so a pass that ends in the second it started still counts as long.
- The pass tests' shared fixture clears `CLAUDE_CONFIG_DIR`, so a run inside an Orca pane uses the fixture's stub
  Codex plugin, not the real one under that profile.

## 0.25.1 -- 2026-10-22

- A past-line marker left behind by a compaction or a restart that never came no longer blocks main's tools: the gate
  reads the current context and clears a marker under the line.
- On a first run with no checkpoints folder, the past-line marker is still written, and a marker that cannot be
  written is reported instead of letting every tool through.
- The restart carry looks up each `done when:` ref once per run, reads the decisions ledger once, and all its lookups
  together, decisions too, stop after 30 s.
- The carry walk gives each open item the distance of its nearest owning file, with no search per closed key, so its
  work and memory grow with the chain, not its square. An item one near branch closes and a longer branch keeps open
  is now carried at its owner's distance.
- The relay's "owner quiet" minutes count only prompts typed at the root of main or of the Chief-of-Staff worktree
  (paths compared after removing `//` and `/./`), not worker prompts such as main-watch's `Signal WARM`, wherever
  the workspaces folder sits. A prompt from a subfolder of either no longer counts.
- Comments no longer carry personal names or ruling ids.

## 0.25.0 -- 2026-10-21

- Issues #218, #221, #222, #227, #231, #232, #235, #237, #239, #243, #244 and #245 shipped in 0.21.0 and 0.22.0.
- Setup asks the Builder's effort right after its model and recommends High for Sonnet; the doctor names where the
  Builder's model and effort come from, and those two `/config` options default to `project`, which keeps the
  project's answer instead of hiding it (#293).
- A restarted main is blocked once with the count of dropped items and the command that lists them, not the whole
  list; on the second stop the missing items are copied into the checkpoint and main restarts. One close line closes
  one item, with its own reason (#252).
- The second-stop copy keys items by subject and reuses the one unresolved Queue heading, so restarts add no
  duplicates (#281).
- The restart checkpoint closes finished items itself (`done when:` an issue closed, a decision answered, a unit
  merged, a commit pushed), keys Queue items `Q-<n>`, has a `dedupe` command, and moves items past ten generations
  to an aged-out file; the stop hook logs the checkpoint's size (#283).
- The stop hook logs the minutes since the last restart; nothing alerts on the "carried automatically" lines (#300).
- On a 200K window main restarts at 140K, under the ceiling of 165K, and a Builder clears at 140K; the context count
  includes the last turn's output (#267).
- Past its line, main may only write its checkpoint: every other tool call is refused until it restarts (#275).
- A unit that passes the gate (a final GO on its tip, a clean tree, no open owner decision, no `Merge: hold`) now
  merges itself into local main, and never pushes. A unit left waiting is gated again at the next tick (#254, #258).
- Routine inbox items (a landed merge, a repeated heads-up) go to a digest instead of waking main (#253).
- A brief's `## Post-merge` lines run after a green merge when they are on the allow-list; any other line is refused
  with exit 5 (#255).
- Redundant steps removed: the rung line, `--verify` run twice per tip, and a plan revision after a GO verdict (#306).
- `ci-watch.sh` watches a commit's CI runs and reruns a failed run's failed jobs once; `decision.sh push-ask` asks
  the owner to push, and refuses when nothing is to push or a merge's check is not green (#259).
- Planning scratch files in the plan worktree are moved aside and no longer block the Builder launch (#284).
- The relay runs `cos-check.sh`, a 50-minute timer check that names a down watcher, prints held FYI notes and counts
  missed messages; with the owner quiet for 30 minutes the relay opens no picker (#290).
- An owner-bound Builder question is recorded for the owner at once, not behind main (#305).
- A merge reuses the closing pass's green suite when that run tested the merged tree itself (same tree hash), and
  `merge-queue.sh --train` tests several units' combined tip once and bisects on red (#307).
- `board.sh` no longer prints the host project's chain-host, offloaded and placement-wait lines.

## 0.24.0 -- 2026-10-21

- #217, #224, #240 and #242 shipped in 0.21.0 and 0.22.0. #263 (the dashboard behind a login) and #269 (tests
  running now) follow in the next release.
- An answer the dashboard could not send says why, gives up after its tries, and can be cleared from the card; it is
  no longer sent again on each refresh forever (#295).
- A project can move from another collector to the plugin's: `dashboard.sh --import <folder>` takes its limit
  history, panel layout and cleared builds, a fresh install keeps the scratch and workspace settings, and the first
  project registered becomes the home project (#292).
- Ledgers and caches reach jq as files, so a long ledger no longer fails with "argument list too long" (#280).
- Claude's files are read from `CLAUDE_CONFIG_DIR` when it is set: transcripts, sessions, settings and
  `.claude.json`, in the scripts, the hooks and the collector (#291). Uninstall takes the plugin's rules, /config
  options and status line out of every profile setup wrote to, and gives each profile its own status line back; a
  move to project scope takes the rules out of every profile.
- Typing in a decision's answer box no longer hides new decisions and notes: the list is redrawn around the box
  (#276).
- A project named `__proto__` no longer breaks the other projects' answers (#277).
- A "Restart collector" button on a page on this machine restarts the collector service, at most once a minute, and
  the page shows the last cycle's time (#294).
- New card "Tokens per unit, 7 days": each unit in flight or finished this week by cost, Claude and Codex apart,
  its stages behind a toggle (#270).
- A merge writes one row per unit to `.claude/metrics/unit-ledger.jsonl` (`unit-ledger.sh`): rounds, verdicts,
  seats and tokens. New card "Review loop, 7 days" lists the merged units, most rounds first (#271).
- `unit-ledger.sh --escaped <unit> <issue>` tags an issue a unit's review let through; the review card lists the
  escapes (#272).
- The Issues card shows the issues opened and closed in the last 24 hours and a 7-day sparkline of both (#273).
- Alerts that cleared in the last 24 hours are listed, folded, under the alerts card with their start and clear
  times (#274).
- The collector reads only what changed since its last cycle: transcripts, guard-block logs and Builder sessions
  from stored offsets, and one terminal list per cycle (#299).

## 0.23.0 -- 2026-10-21

- An exception, allowlist or exemption entry in a guard or its test stands only when its test proves it; the rule is
  in every worker's rules and the Builder's brief (#282).
- Only the owner's yes that names the unit or each issue in its scope is a build order. A launch's `Order:` line
  quotes it, and filing an issue or approving a lesson is never one (#287).
- Every seat verdict and every lone exit notice reaches main (#288).
- From the second fix round on, the Builder's fresh session runs on Opus (#289).
- `seat.sh run` launches a seat, waits, collects and prints one line back (#257).
- A fix round never changes a behaviour the owner has an open question on: the fix hand-off lists the open decisions
  that name the unit, and `merge-unit-local.sh` refuses to merge while one is open, read again just before the commit (#265).
- `builder-launch.sh --from-plan <unit>` takes a judged plan to a live Builder in one call. It installs on main only
  the plan the judge read, or the plan author's revision collected PLAN-DONE after a NO-GO, and refuses a GO beside
  another judge's NO-GO on the same plan. The new `maxBuilders` option in `/config` caps how many Builders run at
  once over all units, counted under one admission lock; an exited Builder does not count (#256).
- Tests run under the merge lock no longer hold it after the merge ends (#301).
- The test runner names every failing case (#268, first part).
- A `review` pass whose GO could not merge runs as the closing pass, and says so (#260, #266).
- A second NO-GO on the same finding class asks the Builder for an approach that fixes the whole class (#261).
- Each finding in a fix hand-off names its test file, its case filter and the command that runs it (#264).
- Seat and Builder panes carry their role and unit as the pane title (#278).
- A Builder that stopped without a DONE line or a verdict is nudged once before main is told, and at most twice per
  pane; a Monitor wait counts as test time in the worktree review (#258, #262).
- A pass that ran long and ended GO hands the Builder to a fresh session, as added work does (#302).
- A class-stop fix uses one retry path, and its test removes each piece of state between two runs (#303).
- Scope added after the first review pass is a follow-up unit, unless main passes `--small --reason` for a change
  under about 50 lines (#304).
- Issues 216, 225, 229, 230, 234, 236, 238, 241 and 246-250 shipped in 0.21.0, and the CI half of issue 268 in 0.22.0.

## 0.22.0 -- 2026-10-20

- The dashboard has a card for the main session and one for the Chief of Staff session: context, today's tokens and
  cost, the 7-day daily average, and today's restarts with the average gap between them (#224).
- A decision can be answered from the dashboard's "Needs me" panel: its options as buttons, the default marked, and
  an "Other" box. Only a page on this machine can send an answer (loopback client, Host and Origin); the phone view
  stays read-only. The first answer wins, the ruling is logged, and main (and the relay) are told; a message that
  could not be sent is listed on the card and sent again on the next refresh (#240).
- The settings that are the same in every project are also the plugin's `/config` options: Builder model and effort,
  review rounds, closing pass, the prompt cache of main and workers and of the relay, ponytail, dashboard address
  and port, and the full suite before the final review. A `/config` answer beats the project's; setup fills the
  empty ones from its answers; the doctor names where each value comes from. Needs Claude Code 2.1.271 or later (#245).
- On Linux, main's startup context no longer loses the lines before its queued messages (the persona, the plugin
  folder): the hook now appends the messages to its output file, where it truncated it.

## 0.21.0 -- 2026-10-20

- Issues #203-#214 shipped in 0.20.0, and #251 was already met. #224, #240 and #245 are not in this release.
- With no Chief of Staff, main may ask the same question again: the repeat guard applies only where a relay holds
  the question (#241).
- `main-watch-helper-hold.test.sh` is split in three (hold, claim, wake), and finished seats are dropped between
  sections, so each file runs well under the per-file cap (#218).
- The limit panel follows the signed-in account: main records its Claude config folder, a reading of another
  account is dropped with its retry note and history, and the panel names the account (#226).
- A worktree used for both plan and build splits its cost by time, each request on its own stage (#242).
- Two dashboard pages folding at once keep both folds (#217).
- A worker's wait budget reads inside shell strings: `bash -c 'sleep 400'` counts against the cache budget (#216),
  and `$'sleep'` and `$"sleep"` read as the word sleep (#215).
- No restart or stopped alert for a pane that has already healed: main-watch reads the session log and a second
  reading before it posts (#238).
- The merge checks its own commit message for home paths and the project's leak words (#221), and closes the
  unit's issues, naming the merge commit; a dry run says which it would close (#239).
- The full suite runs before the final review where it is turned on, and a red run makes the round NO-GO and
  refuses `--verify` (#243); setup asks whether to turn it on, On recommended (#244).
- Each finding carries a class tag, and two NO-GOs on the same class stop the review loop with a class-level
  question (#225).
- `seat.sh collect` keeps the full report at a stable path and records it; `read-verdict.sh --seat` prints it (#236).
- Main checks the merge gate (`builder-codex-pass.sh --verify`) before it offers a merge (#237).
- `seat.sh launch` returns once the pane exists and finishes in the background; `status` shows the phase (#233).
- A new unit opens only on a batch whose Launch line names it (#234).
- Every script prints its usage on `--help` and does nothing else (#222).
- `orca-wait.sh` and `board.sh` print a compact form under 3 KB by default, with `--full` for the whole (#223).
- A relay watcher's wake prints one summary line and keeps the whole text in a file (#229).
- `relay-order.sh` answers a decision with the owner's words and their ruling id, tells main and marks it seen, in
  one step (#231).
- An empty picker answer is no ruling: it prints a retry and leaves the decision open; the relay checks the rulings
  log before a picker, and main-watch raises a picker left open 30 minutes (#232).
- Main's startup print is held under 10,240 bytes in the hook, a part that does not fit becomes one pointer line,
  and rules main does not use every turn moved to Details; checkpoints no longer ask for task ids and paths by
  hand (#228).
- Main's rules open with a five-line do-not list, a merge or test run in main's foreground detaches itself,
  `board.sh --unit <u> --seats` lists a unit's seats, and every BLOCKED message names a command to run (#230).
- Main ends each turn with one status line (#235).
- The merge, a delivered answer and `seat.sh collect` close their own main-watch item task (#227).
- Builders hear the batching advice at the second lone look; a Builder's unranged Read of a file over 400 lines is
  refused with a range; a search for one bare identifier gets a symbol-lookup note; an inline script that writes a
  tracked file is refused toward Edit (#247).
- The batching hook polls for siblings every 100 ms instead of sleeping 1.5 s on a nudging call (#249).
- `BASH_GUARDRAILS_TEST_CASE=<text>` runs only the matching `bash-guardrails.test.sh` cases (#248).
- `red-proof.sh` refuses a whole run of a case-aware test file, and `--batch` runs many proofs in one scratch
  worktree (#246).
- `hook-probe.sh` runs one hook on a built payload with its state in a scratch folder, and a review pass over a
  change to `hooks/` asks for an executed probe (#250).

## 0.20.0 -- 2026-10-19

- Issues #191-#202 and #205 shipped in 0.18.0 and 0.19.0.
- After a pass that ended NO-GO, the inbox drain names a fix round, never "merge it". When the merge check would pass
  the tip under the P2-tail rule, it says that merge is the owner's call, and main's rules say to ask the owner (#212).
- Setup's own preview and apply are no longer blocked by the dependency guard when the test command starts with npm:
  the plugin's own `setup.sh`, named by an absolute or `~` path, is a sender of its quoted answers (#206).
- A planning worktree's settings are compared as JSON, so keys in another order no longer refuse its close (#204).
- No notify question when the Codex wrapper already calls the stable link, and none whose old and new lines are
  the same (#207).
- Setup's marked blocks are replaced where they stand: a run with nothing new writes nothing, the blocks no longer
  swap places or add a blank line each run, and a preview says "would copy" once per file (#208).
- The merge report names rules already in setup's block from an earlier run (#209).
- A saved setup answer equal to the recommended one, ignoring case and surrounding spaces, is one option (#210).
- Helpers answer by their 20th tool call and say `NOT FOUND:` for what they did not find; Builder briefs reuse an
  earlier helper's pointers. `unit-cost.sh` counts cold replies and helpers' repeated searches and overruns. A
  5-minute Builder waiting on a background job, helper or pass gets a `Signal WARM` keep-alive before its cache
  lapses, while a ping costs less than the rewrite it saves. QUIET now comes at 225 s for Builders on the 5-minute
  cache, and never while a background job of theirs runs (#203).
- The dashboard has a phone view: a bottom tab bar (Units, Builds, Alerts, You, More), a More sheet, step chips,
  and tab badges; a refused layout save re-reads and merges instead of dropping the change (#211).
- The batching advice reads commands with their quoted text set aside, so `rg "a|b" | head`, echo separators and
  `for` loops count as looks (#213).
- A worker's foreground call may not wait past the prompt cache: its stated waits are summed against 270 s (540 s
  on the 1-hour cache). A worker's foreground sleep loop is now refused, not advised, and the ask the plugin prints
  takes `--timeout-ms 240000` (#214).

## 0.19.0 -- 2026-10-19

- 0.18.0 stays red on the Linux CI job until this release merges: `install-lib.test.sh` found no project from its fixture folders and passed only in an Orca pane; the helper now names its project. No change to the plugin's behaviour.
- `INSTALL_LIB_TEST_CASE=<text>` re-runs only the `install-lib.test.sh` cases whose name holds `<text>`.
- The batching advice (`batch-independent-looks.sh`) was off in the default hook tier; planner seats (`plan-*`) now hear it at the third single-look turn in a row.
- `wait-test-run.sh` waits 270 s by default, not 540, so one wait never outlasts the 5-minute prompt cache; exit 3 says to wait again.

## 0.18.0 -- 2026-10-18

- 0.17.0 could launch no seat under jq 1.7, the jq of CI's Ubuntu: one line of `worktree-setup.sh` used a form only
  jq 1.8 accepts. 0.18.0 fixes it, and CONTRIBUTING.md says to run the suite once with jq 1.7 first on `PATH`.
- The review prompts ask about callers the change left untouched and about cost over time (#191). A build in
  progress when the plugin updates moves to a new unit, as the existing `UPDATED` rule says.
- #192 shipped in 0.16.0 (the doctor's check for keys the main checkout's `settings.local.json` also sets).
- Every dashboard alert ends with the action it asks for, and the cache-builder alert waits until a Builder's
  24 h input passes its warm-up (#193).
- The inbox watcher, `read-verdict.sh`, `wait-test-run.sh`, the platform audit and a tripwire hook no longer print
  "No such file" for a missing file they read on purpose (#194).
- An alert seen once stays quiet when only its stamp moves; it is raised again 24 h after the relay's watcher last
  told it, as Alertmanager repeats, so one that stays on is a daily reminder (#195).
- `to-main.sh` says when the pane it sent to has a question or permission prompt open, and prints Orca's reason
  when a send fails (#196).
- Setup adds the plugin's role seats that a routing file of your own lacks, checks the routing as it will leave
  it, and records what it added; uninstall takes out only those seats, and a later setup run keeps the earlier
  record. Projects sharing one routing file keep the added seats until the last of them uninstalls, however each
  names it (a relative `COMMANDECK_ROUTING` included); a relative `CODEX_HOME` is recorded as the folder it names (#197).
  A relative routing path an earlier release recorded names no folder it was read from, so uninstall leaves that
  file and its seats as they are and says so; the same for Codex files an earlier release recorded under a relative
  `CODEX_HOME`, which a later setup no longer takes for its own. Uninstall takes a seat out only by its own absolute record that no
  other project's record could share, and names each seat it keeps and why.
- `main-watch.sh` tells the relay once when main has not read finished work after its typed wakes, or has a prompt
  open; the relay's inbox no longer counts main-watch's own notes as sends; `cos-tell.sh` says why a typed send was
  not taken (#198).
- Main sends a self-modification step it was denied to the relay as a note, and the relay applies it only from a
  note its inbox watcher names as main's, by Orca's sender; notes the watcher held from before 0.18.0 print quoted,
  never as main's (#199).
- The relay pane spends no turn on Orca's notice of messages that are all its own: a new UserPromptSubmit hook,
  `cos-own-echo.sh`, acknowledges them and drops the prompt (#200).
- New `commandeck:lean-worker` and `commandeck:lean-checker` agents, with no CLAUDE.md, MCP or skills. Their model
  and effort come from routing's new `lean-worker` and `lean-checker` roles; a general-purpose dispatch is told of
  them; `subagent-usage.sh --start` prints each agent type's first-request input (#201).
- A unit is planned and built in one worktree: plan seats run in `<unit>`, and the Builder's launch takes it over
  with `plan-worktree-close.sh --adopt` once every other check has passed, giving the planner its worktree back
  when the launch fails after that and no pane opened in it. A unit planned before 0.18.0, in `<unit>-plan`, goes on planning there and
  closes as before (#202).

## 0.17.0 -- 2026-10-18

- Worker and Builder panes take your own cuts on top of 0.16.0's: setup asks once for the skills
  (`--worker-skills-off`) and plugins (`--worker-plugins-off`) they turn off and for keep words (`--keep-word
  <word>=<names>`), saved in `.claude/commandeck.json` as `workerSkillsOff`, `workerPluginsOff` and `keeps`; update keeps
  them. `worktree-setup.sh` writes them as `skillOverrides` `"off"` and `enabledPlugins` `false`, and `--keep <word>`
  (or `builder-launch.sh --keep <word>`) brings a word's set back, a plugin the panes cut by default (the business
  plugins, memoir, ponytail) included. The leaves are stored in the worktree's `env`, so a rerun after a list shrinks
  removes the dropped ones; a name you set yourself in the worktree's `settings.local.json` keeps your value. This holds for the browser skills and Stripe too. In a worktree set up before 0.17.0, a default cut, Stripe under `--keep billing` included, stays off under a keep word; set up a
  fresh worktree to bring it back. The plugin ships no names: with no answer, nothing new is cut.
  The README says plugin skills cannot be turned off one at a time, only a whole plugin.

## 0.16.0 -- 2026-10-18

- Worker and Builder panes start with less context: `worktree-setup.sh` turns off the Stripe plugin and the
  `computer-use`, `built-in-browser` and `chrome-browser` skills of `anthropic-skills`, turns auto memory off, and, where
  the ponytail plugin is on and setup's answer is yes, swaps its full text for a summary of about 1 KB
  (`templates/ponytail/SUMMARY.md`). Main, the relay pane and a `--keep all` seat keep everything.
- New `--keep <billing|all>[,...]` on `worktree-setup.sh` and `builder-launch.sh`: `billing` keeps the Stripe plugin,
  `all` changes nothing above. The list is stored in the worktree's `env`, so a rerun without the flag keeps it, and
  a rerun that passes the flag replaces it. A rerun removes every leaf the script owns before it writes the current
  set; a `skillOverrides` entry you set yourself stays. The script now refuses an argument it does not know.
- The briefs say auto memory is off in a worker pane: a Builder asks main for a fact the brief lacks, and main copies
  every memory fact a unit depends on into its brief.
- The doctor, and setup under Needs you, warn for every key `worktree-setup.sh` writes that the main checkout's
  `.claude/settings.local.json` also sets with a different value (#192). It replaces the check for a prompt-cache
  TTL there, with the same message for that key. `worktree-setup.sh --print-settings` now prints the relay pane's file too.

## 0.15.0 -- 2026-10-18

- Setup and update ask the prompt cache per role: 5 minutes for main and every worker pane (Builders included,
  replacing their 1-hour pin), 1 hour for the relay pane, each with a Leave as is that writes nothing. The flag
  values change: `--cache-ttl 5m|leave`, and a new `--relay-cache-ttl 1h|leave`; the old `recommended|default`
  is refused. An install that chose the old answer is asked again under Needs you, and setup's own earlier 1-hour
  value moves to 5 minutes only on a 5m answer.
- Rewriting the relay's `.claude/settings.local.json` keeps its other `env` entries.
- The doctor, and setup under Needs you, warn when a TTL in the main checkout's `.claude/settings.local.json`
  would override the per-worktree answers, when the relay pane would not run on the 1 hour chosen, and when an
  `env` TTL in the user's or the project's settings, or a `promptCacheTtl` or `subagentPromptCacheTtl` in main's
  local settings file read after the project's, keeps main on a value other than the 5 minutes chosen.

## 0.14.1 -- 2026-10-18

- Main's startup print is back under the 10 KB hook limit (13,227 bytes before; each role is now under 9,700): the
  plan-before-build detail, the checklist and four more rules moved below main-session.md's Details, with one pointer line. CI runs `scripts/startup-size.sh`, so a print over 10,240 bytes fails it.
  An owner's own main-session.md is also pointed at the plugin template's Details for the moved rules.

## 0.14.0 -- 2026-10-18

- Setup: the fast-tier question for plan seats offers None first (#169); a dashboard choice sets the bind address too
  (#172); turning the dashboard off stops collecting the home project and removes the job when no project is left
  (#173); `generatedFiles` survives setup and update (#174).
- Setup and update offer to rebase an out-of-date relay worktree on main, with the commits it is behind; only a yes
  runs `scripts/relay-sync.sh --rebase` (#170).
- Auto mode: a setup question adds two plain-English lines to the classifier's list in `~/.claude/settings.json`,
  kept with `"$defaults"`. Leave as is changes nothing; taking them out removes only setup's lines. The doctor warns
  about a list without `"$defaults"` and about `autoMode` in a project file.
- The doctor flags a CLAUDE.md, rules file or global CLAUDE.md over 200 lines, a MEMORY.md past 200 lines or 25 KB,
  and tool search switched off; it points to `/skill-doctor`.
- Codex limit alerts follow Codex's own billing mode (#171). The dashboard's review time keeps a retried pass (#187).
- Auto plan tier reads panel triggers in sub-headings (#175). Planning offers each seat its own default model (#176).
- The pane budget hook counts turns only when a pane is over budget (#177). A branch diff over the reviewer's input
  limit goes as a file list to read file by file (#178).
- The typed Codex pointer carries the seat tag (#179). A verdict is printed in one form (#180). The Builder's ledger
  row sums every session it recorded (#181). An answer goes to the planner it names (#188).
- worktreereview: finds the archive at the merge script's path (#182), counts a Claude reviewer's passes (#183),
  refuses an unknown project (#184), writes under `<project>/<unit>` (#185), reads the batch template's item lines
  (#186). Claude no longer starts the skill on its own.
- Instruction files: the templates are held to 200 lines, and AGENT_STARTUP.md says what a compaction keeps (#189).
  A lean `commandeck:helper` agent starts without CLAUDE.md and stops at 40 turns (#190).
- CI runs `claude plugin validate .`, and this repo's merge check runs the version check first.

## 0.13.2 -- 2026-10-17

- A planning card names every plan seat with its model, effort and running or done state, not only the newest, and
  its Planning stage shows its time and cost while the seats run. A seat's row says "running" until its collect. A
  Codex seat binds its own log into its record, so its spend is its own. No driver badge exists to remove. (#168)
- Codex spend also reads the review home's sessions (`COMMANDECK_CODEX_REVIEW_HOME`, default `~/.codex-review`),
  counted once. A Codex or Claude folder that cannot be searched marks the week and the unit incomplete instead of
  reading as not installed. A typed seat pointer carries its task id. (#168)
- main-watch posts nothing while a project's own watcher holds a live claim: finished, stopped and stalled items
  stand down too, not only heads-up notes. An item the owner cannot have seen is posted once the claim ends;
  one it posted is reminded again once the claim ends, until main closes its task. (#167)
- Main tells each planner to name a fitting mattpocock-skills skill in the plan when that plugin is installed; an
  owner who kept their own planning rule keeps it.
- The merge check runs a changed `.test.mjs` through its `.test.sh` wrapper.

## 0.13.1 -- 2026-10-17

- Fresh-round hand-off waits while the Builder's pane is busy, ends when the pane is gone or Orca fails five times in
  a row, and runs one at a time per pane. (#157)
- The watcher no longer posts "stopped without reporting" while a Builder waits on a review pass it started, for up
  to an hour. (#158)
- A fresh-round failure notice reaches main as a question, with the command that re-runs the hand-off. (#159)
- orca-wait shows every message that cites a ruling id or comes from the relay's pane, and keeps every message it
  hides in main-watch/messages/hidden.jsonl, which its summary line names. A batch too large for a command line
  drains instead of replaying forever. (#160)
- Project lookup from outside a checkout falls back to Orca's entry for the pane, and its failure names where it
  looked. (#161)
- plan-worktree-close.sh finds the plan author's pane when Orca lists its worktree only in worktreeId or ptyId. (#162)
- read-verdict.sh: on a screen that may end inside a fence, a GO is not read as the verdict; other verdicts are. (#163)
- merge-unit-local.sh writes the Builder's ledger row with its seat tag, so it names the Builder's own session. (#164)
- The Chief-of-Staff poller always shows a message sent to its own handle, FYI or not. (#166)
- main-watch posts no heads-up while a project's own watcher holds a live claim in <scratch>/heads-up-owner, and says
  so once; a note the owner cannot have seen is posted once the claim ends. (#167)
- merge-unit-local.test.sh is back with one fast case: the Builder's ledger row.

## 0.13.0 -- 2026-10-17

- The merge check (`testCommand`) is now `bash scripts/run-shell-tests.sh --changed`: it runs only the shell tests the
  change touches, and each touched script's or hook's same-name test. The whole suite stays
  `bash scripts/run-shell-tests.sh`, and CI still runs it on every push.
- Removed the three slowest shell tests: builder-launch.test.sh, suite-rerun-guard.test.sh and merge-unit-local.test.sh.
- Setup names the paved-road template to start from when `.claude/paved-road.md` is missing (#155).
- The dashboard shows a unit's planning as its Planning stage: on the plan card, first on the Builder's card and in
  its cost total, seat by seat, including relaunches and seats in their own Codex home (#156).
- `seat.sh collect` with no `--marker` closes on the marker the last wait proved from a finished turn; a wait that
  timed out, or a reply that only quotes the marker (a fenced one on screen too), saves none.
- `seat.sh` finds a seat's sessions in the Codex home its role is routed to (`codexHome`).
- The dashboard stops on a Mac with BSD stat, naming GNU stat, before it writes anything.
- main-session template: a planner's size target is soft.

## 0.12.0 -- 2026-10-17

- Plan before build: `plan-tier.sh <batch-brief>` answers "Write a plan first?" with No plan, Plan + judge or Panel,
  from the triggers in `config/plan-triggers.tsv` (or the project's own `.claude/plan-triggers.tsv`), going one tier
  up when unsure. Plan seats (`plan-author`, the judges) run in a planning worktree `<unit>-plan` cut from main, with
  one judge round and one revision. A plan is never a build order.
- `builder-launch.sh` closes the unit's `<unit>-plan` worktree and its panes once the Builder's pane is open. It keeps
  the worktree, with one REFUSED line, when it holds a file that is not identical on local main or a pane does not
  close. A rejected plan's worktree closes by hand with `bash scripts/plan-worktree-close.sh <unit>` (`--dry-run`
  removes nothing). An unreadable, empty or error pane list counts as "panes not closed", never as "no panes".

## 0.11.2 -- 2026-10-16

- `scripts/platform-audit/verify.sh` refuses a verdict with two rows for one finding: the later row silently
  replaced the earlier one, so a confirmed P1 could count as refuted and the audit still recorded HEAD.
- `hooks/suite-rerun-guard.sh` starts Python once per call, not three times, and forks less: about 40% faster per
  call, and its self-test drops from about 77 s to about 50 s, well under the shell-test runner's 120 s limit. Its
  Python no longer imports a `shlex.py` or `re.py` from the project folder.
- `builder-launch.sh` refuses a raise whose brief or evidence cannot be read, keeping the evidence history, and
  refuses a directory where a record belongs instead of writing inside it (#152, #153).
- `dashboard.sh` keeps an unreadable `unit-cost.json` as it is instead of overwriting it with only the latest units'
  costs; a corrupt one is still reset (#154). `--unregister` refuses an unreadable registry instead of emptying it.

## 0.11.1 -- 2026-10-16

- `scripts/platform-audit/run-audit.sh` runs its verifiers under bash 5.2 (ubuntu CI) too: bash 5.2 could not re-read
  `verify.sh`'s per-area function, so no verifier ran and every audit failed.

## 0.11.0 -- 2026-10-16

- Breaking: `builder-launch.sh` refuses a batch brief with no `## Prior art` section, a brief written before 0.11.0
  too. Add the heading to the brief and under it name the governing standard, the library or service the project's
  `.claude/paved-road.md` approves, and why the batch builds instead if it does; then launch again.
- A paved-road registry, `templates/paved-road.md` (empty), is copied to a project's `.claude/paved-road.md`: for each
  area, the standards that govern it and the library or managed service it builds on.
- The batch brief template has a required Prior art section, and `builder-launch.sh` refuses a batch without one;
  the Builder brief says that section binds.
- Every review pass, Codex or Claude, asks whether the change hand-builds what the registry or a published standard
  covers, and has such a finding cite the registry row.
- `scripts/platform-audit/run-audit.sh [--dry-run]` audits each area of the registry whose files changed since the
  last recorded audit: one read-only auditor (routing role `audit-auditor`) per area, then one verifier
  (`audit-verifier`, read tools only) that tries to disprove each finding, merged into one report. A change to the
  registry or the areas file audits every area again. An agent that fails, or whose output lacks the template's
  sections or a verdict for each finding, fails the audit and records nothing; `--dry-run` lists the areas and
  launches nothing.

## 0.10.0 -- 2026-10-16

- Each build in Builds in progress folds to one line on its own toggle (name, seat, stage, issues built, cost so far,
  last sign); a finished build folds by itself, and the owner's choice is kept with the panel layout (#150).
- `builder-launch.sh --effort high --reason '<one line>'` raises one Builder above the setup default (medium or high
  only); the brief and the evidence file record the override, the launch prints the effort it uses, and the
  dashboard marks the build raised by main (#151). `seat.sh launch builder` holds a launch by hand to the same
  floor. A risky launch's second call opens the Builder at the effort the first recorded, or rewrites the brief and
  logs the change in the evidence before it opens at a new one;
  it refuses while that Builder already runs, and a retry after a failed write finishes every record still owed.

## 0.9.0 -- 2026-10-16

- Main's Stop hook holds a turn once when the owner's message the Chief of Staff passed on has no reply sent back,
  and the relay's watcher flags every main turn that ended with nothing sent to it, with main's last words (#138).
- The limit card shows each 7-day tile only where that provider has a subscription window; a failed read still shows it (#139).
- The Chief of Staff's inbox watcher wakes on any message main's pane sends to the run, whatever its subject (#140).
- The Chief of Staff's Stop hook requires all four watchers, each checked by its own pid file for this project (#141).
- `read-verdict.sh` reads main's pane from the newest session log in main's checkout (#142).
- A script run from outside the project finds it from Orca's worktree id when Claude Code gives no project folder (#143).
- The Stop hook's block names each watcher's start command by the stable plugin link, which survives an update (#144).
- The closing run cites a touched test file already green on the current tree instead of running it again (#145).
- Setup asks the Builder's effort (medium by default), and every Builder launch runs at it (#146).
- Setup asks the Builder clear line (180K by default, or off): past it the Builder is told to hand off to a fresh
  session of its pane, and the dashboard's unit card shows its context against the line (#147).
- Setup asks the issue sizing line (40K by default, or off): the batch brief sizes each issue, and the Builder launch
  flags an independent issue over the line to main, the split proposed (#148).
- The leak check searches a PNG's text chunks (tEXt, zTXt, iTXt) with the word list; a new or changed image is for the owner to review (#149).
- Codex fast mode reads Codex's config.toml as TOML: a quoted `"service_tier"` key or a `'fast'` literal now counts,
  the default profile's tier wins over the top-level one, and a tier set only in an unused profile no longer does.

## 0.8.1 -- 2026-10-16

- The tests no longer install or uninstall the plugin or run setup.sh or uninstall.sh whole: small checks of
  the functions they call take their place, and the Builder brief and CONTRIBUTING.md say not to write new ones (#127).
- The dashboard's merged-since-push list was already a pane of its own, Next push (#128).
- A unit card keeps its Stage band in view and folds the activity rows into a closed Details (#129).
- The stage list names each Codex pass with its round's verdict, GO or NO-GO, or running (#130).
- The search guard counts reads sent together in one turn as one lookup; a whole-repo search is still refused (#131).
- A fix-round session starts from its hand-off and opens the brief and evidence file only when a finding needs them (#132).
- `builder-codex-pass.sh --check` runs a launch's own checks and stages, commits and sends nothing (#133).
- The suite re-run guard checks the head of every suite in a chain: `npm test && ! npm run typecheck` is no
  longer recorded as a pass (#134).
- builder-add-work.sh, answer-worker.sh and to-main.sh find a Builder's pane from its launch record (#137).
- The README has an Updating section: the two steps of a plugin update, and going back a version.
- update.sh shows setup's Needs you list, a failed add-on install or update among it, where it used to hide it.
- The README shows the dashboard and Orca, in a What it looks like section.

## 0.8.0 -- 2026-10-16

- No script can remove a main checkout any more. `dashboard.sh --project` run by hand
  with no DASH_NOW removed the folder it was given (how ~/repos/Commandeck was lost);
  every computed removal now refuses a checkout, a git folder, HOME or `/`, and the
  merge refuses a unit folder that is not a linked worktree.
- A fix round the Builder's pane never took is now told to main, with Orca's own answer,
  instead of only written to a log.
- The suite re-run guard records a run as passed only when its exit status is the
  suite's own: a piped or chained failing run is no longer taken for a pass.
- Escaped quotes no longer hide a second suite from the re-run guard.
- A COMMANDECK_MAIN or COMMANDECK_WORKSPACES spelled with `/./`, `//` or a trailing `/`
  now matches the paths Orca, transcripts and setup's records give, on both sides of
  each compare; nothing stored is renamed.
- Main can clear a review finding it ruled out: a line under "Cleared findings" in its
  rulings file. The merge then counts it as cleared, not as a blocker, and the reviewer
  is handed it with the stated limits.
- A merge of Commandeck itself runs the shell suite (`.claude/commandeck.json`
  testCommand).
- setup.test.sh (600 s) and merge-unit-local.test.sh (300 s) carry their own allowance
  (`# timeout:`), so the runner no longer reports them HUNG at the 120 s cap; every
  other file keeps that cap.
- Setup installs every add-on and updates each to its latest on every run (`--addons`
  narrows the list); no command names a version. codebase-memory is updated only while
  no session is open, and setup says FAILED when a new session cannot reach it.
- Dashboard: a long Builder name in "Who holds what" no longer squeezes the issue
  number and title to a letter per line; the name is cut short, whole on hover.
- Dashboard: a build's "Cost so far" shows its Claude and Codex parts.
- Dashboard: a Builder's issues built are also read from its evidence's Issue and
  Status table; a row that says partly built, blocked or not built does not count.
- The relay pane follows the owner's ponytail setting instead of turning it off, no
  profile names typescript-lsp, and the worktree summary has its space back after
  "memoir off,".

## 0.7.2 -- 2026-10-16

- Main's startup text is 497 bytes shorter (main-session.md, 10,198 to 9,701
  bytes for the main seat), and states every rule it stated before. A rule you
  keep your own wording for (`--rules-drop`) stays out after its rewording,
  until you answer keep both (`--rules-keep`) for the reworded rule.
- Main's prompt banner is about 0.4 s faster (1.26 s to 0.83 s, 5-run means):
  its three local checks run beside the Orca calls. It prints the same text.
- COMMANDECK_WORKSPACES given ending in `/` or `/.` no longer hides this
  project's worktrees from any script (0.7.0 fixed the prompt banner only).

## 0.7.1 -- 2026-10-16

- A decision reopened or re-asked in the second it was last asked now waits
  for the next second and takes that as its new ask time. The Chief of Staff's
  watcher puts it to the owner again, and an answer read before the reopen
  cannot close it (the 0.7.0 Linux CI failure).

## 0.7.0 -- 2026-10-16

Setup asks better questions, shows every change before it makes one, and can
merge its rules with yours instead of replacing them.

- Setup checks the requirements before its first question and says what it
  found: your own startup files, your project rules, your global
  `CLAUDE.md`, your model's context window when a setting names it, and
  whether Codex and its fast mode are ready. Each question explains its
  choices, marks the recommended one "(recommended)" and offers it first,
  and is asked only when it applies. While setup asks, the picker's stray-keypress option is
  off; it comes back when setup ends, fails or is cancelled.
- `setup.sh --plan` prints every file a run would create or change (a diff
  for a changed one), every copy, job and add-on, and writes nothing. The
  skill shows it and asks Apply, Change an answer, or Cancel.
- Your rules: setup can merge the plugin's rules with your `CLAUDE.md` and
  `.claude/rules/` (exact matches are left out; you choose for a rule that
  only says the same in other words, or disagrees, seeing both texts, and a
  rerun keeps your answer). Only a rule a session really loads counts: not
  one in a path-scoped rules file (or one whose frontmatter setup cannot
  read for sure), one a Builder's settings leave out, or
  one under main-session.md's "Details (not injected)". It also merges with
  your own
  `AGENT_STARTUP.md` and `.claude/main-session.md` (merge, replace or skip,
  asked each time). Global rules gain merge. Your own text is never changed:
  the plugin's rules go in marked blocks, a copy of your file is kept beside
  it first, and uninstall takes out only the blocks.
- Project permission rules now go in `.claude/settings.local.json`, which git
  never sees, since they name this machine's plugin folder; a rerun moves
  them out of `.claude/settings.json`. A new scope moves them instead of
  asking for an uninstall first.
- The dashboard, ponytail and add-ons are questions now. Add-ons you pick are
  installed for the main checkout and reported as installed or failed, with
  the command (#113). The relay pane explains why its servers read as
  blocked "by enterprise policy", and the serena line setup and the doctor
  print reads the saved config (#114).
- Setup ends with a short summary: done, needs you, optional, and how to
  change an answer later. The doctor says when your own startup file loads
  instead of the plugin's.
- Setup asks for the prompt-cache lifetimes: recommended is 1 hour for main
  and the Claude panes and 5 minutes for subagents, written to the project's
  `.claude/settings.json` (a value you set stays; uninstall takes out only
  setup's). On real transcripts 5 minutes cost main about 19% more than 1
  hour, and 1 hour cost subagents about 8% more.
- Small build can be turned off: every first pass then has three reviewers.
- The dashboard loop picks up a changed view file on its own, without
  `--install`.
- Removed: the hook that refused main a read inside a worker's worktree.
  Restored: the hint that a plugin script answers `--help`, when main reads
  one.
- The prompt banner lists only this project's Orca worktrees, also when the
  worktrees folder is named with a trailing slash.
- The whole-disk search guard refuses, and names realpath, when `realpath -m`
  does not work, instead of blaming the path.
- `startup-size.sh` measures each seat in its own folder, so only main's row
  shows the prompt banner.
- The Builder brief template asks for the brief and every file it names in the
  first turn.
- The worktreereview step marks each item the first render leaves unreviewed,
  then renders again.

## 0.6.0 -- 2026-10-15

Every open issue in one build, plus the tooling fixes from the project this
plugin grew out of: cost by stage on the unit card, a fresh session for each
fix round, safer merges and a set of decision-ledger and inbox fixes.

- Decisions: the watcher no longer re-fires an open decision on every restart
  (#105); `decision.sh answer <id> <answer> --correct` replaces a wrong answer
  and keeps the old one in its history (#103); a Builder's question lands in
  the ledger as waiting on main and is never counted as the owner's (#92); a
  prompt closes a plain-chat ask only when it names its id; a re-asked
  decision passes for the picker whose header names it; the ruling log is
  appended under a lock.
- Inbox and waits: a bare inbox check that never acknowledges its batch is
  blocked and points at `orca-wait.sh` (#89); a Builder's hand-written poll on
  test output is nudged to `run_in_background` and the new
  `wait-test-run.sh`, which also checks the runner is still alive (#84); notes
  to the relay pane go to main's run and are confirmed stored (#102);
  `answer-worker.sh` says "queued, not read yet" for a mid-turn pane (#101);
  main is woken by mail left unread two minutes while it is idle.
- Builder rounds: a NO-GO pass from the Builder's own pane writes a hand-off
  that stands alone and starts the next round in a fresh session of the same
  pane (`builder-fresh-round.sh`); `builder-add-work.sh <unit>` hands added
  work over the same way. Every later pass is handed the evidence file's
  `## Main-only (deferred)` list as known. `red-proof.sh` shows a test catches
  a break from a scratch copy of the tree. `review-cap.sh <unit> <n>` raises
  one unit's round limit (#100). A Codex pass first proves Codex answers.
- Brief template: a red hang test sets its own timeout (#109); each evidence
  heading is written when its item turns green (#90); a changed setting keeps
  reading the deployed format, and the reviewer checks it (#104); an answer
  after the done marker is still read (#93); a file that times out twice is one
  question to main; each test result carries the machine's load.
- Merge: main is fetched and fast-forwarded before branching or merging (#99);
  a GO followed only by regenerated build files is accepted (#108); the merge
  title is the brief's heading, not the pass subject (#88). `board.sh` shows
  each unit's last pass result (#91).
- Dashboard: the unit card and the Builds panel show cost so far and cost per
  stage, with a full-width stage list and a Total row when stages are narrow
  (#94); dotted and prefixed model ids are priced (#96); the build timeline
  starts when the build started (#95); usage-limit tiles are hidden when
  Claude runs through an API (#97); a Builder under 95% cached over 24 hours
  raises a warning; the host-load alert is gone (swap still alerts).
- Setup and launch: Builders and the headless reviewer run with the advisor
  switched off when they name none (#85); every review flag and threshold takes
  `off` (#87); typed values are asked inside the picker questions (#86).
- Hooks and tests: main reading a worker's code is refused (#76); a read-only
  Codex run also drops Stop hooks off its keep-list; the dependency guard
  returns at once for a command naming no package manager (#81); the tested-
  tree record ignores the evidence file and counts chained runs (#107); the
  suite-rerun key keeps every argument; the leak test ignores runtime files
  (#79); setup.test.sh no longer hashes a directory (#80).
- /worktreereview: every "Where it could shrink" item is reviewed after each
  report (#106); refusals are counted by hook and reason; cut windows come off
  command and helper seconds.

## 0.5.0 -- 2026-10-14

Every open issue in one build: the read guards are gone, the build review runs
only on request, three GitHub panes and a new unit card on the dashboard, and
a long list of fixes to the merge, the pass script, the watch and the cost
readers.

- Read guards removed (#76): no 150-line shell read cap, no shell
  symbols-before-read hook, no symbols-first rule for Read, Grep and Glob. The
  test heap cap, the repo-wide search block, the main/worktree boundary and the
  other hooks stay. A here-document sent to a shell through `>(...)` is now
  judged as commands (#5); a nested substitution after `cd ..` was already
  judged in the right folder and now has a test (#4).
- The hook fire log records an "ask" answer as `ask` (#75), and a guard test
  fails a hook that prints "ask" without its marker. Claude Code 2.1.300
  (#71): the two hooks that return `updatedInput` send only valid keys
  (checked live for the agent model guard), and every transcript reader skips
  the new `api-request` rows, so request counts and prices match the assistant
  rows.
- The build review runs only when the owner asks (`/worktreereview <unit>`),
  never from the merge, and sends no flag message (#78). It keeps the full
  pass text and lists every pass after the closing one (#64); waits on a pass
  run elsewhere or a review tool that is down are their own bucket (#55); the
  share-of-clock flag also needs 10 minutes of tests or idle and names the
  largest command (#63); idle after DONE is cut only where an owner decision
  was open (#70); a review saved before the waiting field renders it as
  unknown (#16). Lessons become issues only with the owner's approval, with an
  on-demand sweep (#68), and the lessons page can be written by a separate
  writer session from a shipped handoff (#69).
- Dashboard: the unit card is a run trace (#73); three GitHub panes, the merge
  line, who holds what and the next push, read through `gh` and say so when it
  is missing (#74); an issue in Issue by Issue opens on GitHub (#72); a stale
  page no longer writes its old widths over a newer reset (#2); a replay of
  expired clears from a stale tab no longer pushes out newer ones (#6).
- Merge: a deletion named under "Files deleted" in the unit's evidence file is
  accepted, and the merge says which file named it (#67); a failure after the
  squash commit exits 3, and the queue says the unit merged (#22);
  `proof-run.sh` prints the three-argument `--verify` (#21); `board.sh` says
  what it writes (#23).
- Watch: only the Builder's own DONE marker ends a helper hold (#44), and a
  Builder that works again clears its hold (#45).
- Pass script: a cache fallback warning no longer ends up in the model id
  (#46); after main changes the brief or its rulings, the next review pass
  reads the whole branch (#58); each pass prints the files the round changed
  and flags a round of comments only (#62); `Different fix r<N>` and
  `Other cases checked r<N>` evidence lines reach the reviewer (#54, #57); the
  README says why a build that changes the review prompt makes the next build
  run one new pass (#19).
- Builder: Opus at effort high with no advisor, whatever an older set-up
  stored; a live Builder pane is refused when the configured model changed
  since its launch (#17); the brief no longer names the model (#20) and carries
  the test-run rule (#77, also in the shipped rules), the shared-Mac test
  rules (#53), and rules for questions answered another way (#56), documented
  commands (#59), starting helpers together (#61) and rulings that leave
  something as it is (#60).
- Cost: a request seen under its request id and its message id counts once,
  across cache reads (#51), and an older cache is rebuilt (#52).
- Fixes: the leak test compares folders by identity, not letter case (#7);
  `/test-audit` reads a `read=` field that is not plain ranges as not clean
  (#8); `project-main.sh` clears Git's routing variables before it probes
  (#13) and pairs a stand-in main under temp only with a workspace under temp
  (#14); macOS CI runs setup with no Homebrew on the path (#65). CI installs
  jsdom again so the dashboard page tests run.

## 0.4.5 -- 2026-10-14

Setup asks how the review loop runs, the default Builder has no advisor, and
messages to a restarted main or Builder are no longer lost.

- Setup asks the review-loop settings instead of fixing them: the most review
  rounds a build may run, whether a closing pass reads the whole branch, the
  small-build line for a one-reviewer first pass, and the three thresholds
  that flag a finished build for a written review. Each offers today's value;
  taking every default saves nothing and changes nothing. Numbers are saved as
  typed, and a value the loop cannot use is refused. With no closing pass, the
  narrowed pass that ends GO merges once narrowed passes have read every
  commit after the first pass.
- The default Builder is Opus at effort high with no advisor, a risky build
  included; `--small --model sonnet` is unchanged.
- Claude Code 2.1.299: the ruling log skips a prompt that is a slash command
  seen before it expands, and the README points at the built-in idle
  compaction.
- Handoff (#43): the startup context names the plugin by the stable link
  `~/.commandeck/plugin`, a pane that is still main after a handoff says so,
  the new main's first line confirms the handoff, and the main-pane guard
  points to `/handoff`.
- Global CLAUDE.md and rules (#48, #49): setup offers the plugin's general
  instructions and working rules, as a new file or a marked block; it never
  changes the owner's own text, and uninstall takes out only its blocks.
- Lost messages (#50): `to-main.sh` finds main's pane when it sends, and
  queues the message when main is down; the next session shows the queue and
  unread mail to its earlier handles first. `answer-worker.sh` takes a unit
  name the same way.
- Codex notify wrapper (#66): doctor reads a notify line that calls the
  owner's wrapper script and warns only when the wrapper calls no hook or an
  older one. Setup asks before it changes such a wrapper, and uninstall names
  the line to take out of it.
- A fast doctor test covers the common path.

## 0.4.4 -- 2026-10-14

The shell test suite runs in under five minutes.

- The suite had grown to about 70 minutes. It now keeps only the critical
  tests: setup and uninstall complete, each blocking hook blocks what it must
  and lets through what it must, the leak test, every shell file parses under
  Bash 3.2, the version check, and a merge is refused without a passing
  review. 125 shell test files were deleted, with the Node and Python tests
  and fixtures only they used; the kept hook and setup tests were trimmed to
  their critical cases. The Builder search guard's block cases, which lived
  in a deleted Builder test, now have a small test file of their own.
- The Doctor, dashboard, main-watch and proof-run tests are gone, with the
  tests of the advisory hooks that never block. Uninstall is tested at project
  scope only.
- CI no longer installs jsdom; no kept test uses it.

## 0.4.3 -- 2026-10-14

A Builder waiting on its helpers is no longer reported as stopped, and Codex
behind a proxy finds its model.

- A Builder that starts helpers in the background ends its turn to wait for
  them (#41). The watcher posted it to main as "stopped without reporting",
  or as finished. It now reads the Builder's event log first: while a helper
  is out, and that helper wrote a row in the last 20 minutes, it waits and
  checks again on the next tick, for an hour at most; a wait that runs out
  with no DONE line is posted as stopped. A Builder that stopped with no
  helper out, or printed its DONE line, is still posted at once.
- A helper can log a stop and then go on working, then stop again. The
  Builder card took the first stop as the finish. It now counts a helper as
  running until a stop that none of its own calls follows. Stop rows from
  ids that never started (most of them) are not helpers and change nothing.
  The dashboard no longer shows an idle Builder as waiting on main while its
  helper or Codex pass is still running.
- Codex behind a proxy (#42). When Codex's `config.toml` sends it through a
  proxy (a `model_provider` with a `base_url`), the model family is looked
  up in the proxy's own model list, newest version first, then in
  `models_cache.json` as before. A GitHub Copilot API proxy is asked with
  no key; a regular proxy gets the key its `env_key` names, as a bearer
  token.
- Setup takes a model id for a Codex role: `--codex-model
  codex-reviewer=gpt-6.1-sol`. It is saved in the project's own
  `.claude/commandeck.json`, so a plugin update keeps it, and it wins over
  `routing.json`, a hand edit of it included. `--codex-model
  codex-reviewer=` clears it.
- Doctor and setup say whether Codex goes through a proxy, and a refusal
  names the fix that fits.
- Claude cost behind an API proxy (#47). A proxy writes session lines with
  no `requestId`, and the "Cost today" tile showed $0.00. A line with no
  `requestId` is now counted under its `message.id` (a streamed request
  writes several lines with one `message.id`; the last holds the final
  usage), else its `uuid`, so a request is never counted twice. A log where
  every line has a `requestId` totals as before. Dollars are still a
  list-price equivalent, not a bill.
- `gpt-6-luna` is priced from its published list price (read 2026-10-14);
  a new luna version takes the tier's price and says so.
- The doctor no longer prints the "Python 3.11 or newer" fault twice when
  Python has no tomllib.

## 0.4.2 -- 2026-10-14

CI is green again on Linux. The plugin works the same for the owner.

- The Mac preflight in `scripts/paths.sh` (and the doctor's copy of it)
  read the self-tests' pretend system, `COMMANDECK_HOST_OS`. So a Linux
  runner that a test called a Mac asked for Homebrew and stopped. It now
  asks `uname`, the machine it runs on.
- `plugin.test.sh` pinned version 0.3.0, so every release broke it. It now
  reads the version from the manifest and checks the README badge and the
  newest CHANGELOG entry against it.
- The day tile's test expected no model name after "requests unpriced". The
  tile names the unpriced models, as 0.4.0 says, so the test now expects
  the name.
- `.claude/metrics/seat-events.jsonl` is ignored by git.

## 0.4.1 -- 2026-10-14

Codex prices by tier, and a decision names a unit only as a whole name.

- A new Codex version of a known tier was unpriced (#36). By the owner's
  ruling it now takes the tier's price: `gpt-6.2-sol` is priced as `sol`,
  with no new row. The dashboard's week note and day tile and the build
  review page say how much of the total is priced by tier, not by exact
  version (`tierUsd` in the dashboard's data). A name with no known tier
  stays unpriced and the total stays marked partial. Claude rows are
  unchanged.
- A decision for `unit.-v1`, `unit..v1` or `unit.` counted as one for
  `unit` (#40). A unit's name now matches only as a whole token of the
  launcher's name alphabet (`A-Z a-z 0-9 . _ -`). A full stop after the name
  reads as part of it, so the worst case is a missed cut, never a wrong one.

## 0.4.0 -- 2026-10-14

Prices from model names, waits that are not build time, and the Mac's old Bash.

- A Codex model's price came from one row per model id (#36). It now comes
  from the parts of the name: the version and the tier word, then the mode
  and the prompt size, through one small rule table in
  `scripts/dashboard_limit.py`. Only a published version and tier is priced:
  `gpt-6.2-sol`, `gpt-6.1-astra` or a name with any other part (`-mini`, a
  date) stays unpriced, and the total says it is partial and names it. The
  per-id Codex rows are gone; every Claude row is as it was.
- The build review counted time the Builder spent waiting on the owner as
  build time (#39). `collect.py` takes `--exclude START=END` (repeatable) and
  finds windows itself: an idle gap over two minutes after the Builder's DONE
  line, or inside an open decision that names the unit. It never cuts while
  any session has a background job or a Codex pass running, and a found
  window cuts only idle seconds. The cut comes out of wall clock, shares,
  flags, stage, pass and gap times; cost is unchanged. The page and
  `result.json` (`cut`, `cut_s`) list every window and why; `SKILL.md` states
  the rule. A cut request loses it from its wait and thinking too.
  Not cut yet, and the page says so: a helper's request and tool subtotals,
  and command seconds inside a cut review pass. The decisions, and the round
  archive, are read from the reviewed project's main checkout, found from its
  worktree; once the worktree is removed, only from one given with `--main`.
- Eleven shell files did not parse under the Mac's own Bash 3.2, `setup.sh`
  among them (#38). Each is rewritten to 3.2's syntax: `;;&` as two `case`
  statements, a `(pattern)` in each `case` inside `$(...)`, a here-document
  inside `$(...)` moved into a function, and `${X:-$( { ...; } )}` in two
  steps. `run-hook.test.sh` runs `/bin/bash -n` over every shell file, in the
  macOS CI job too. The test runner still needs Bash 4 and, with none to
  restart under, now says so and stops.
- `.claude/routing-log` is in `.gitignore`; only a local exclude covered it.

## 0.3.0 -- 2026-10-13

After setup: the first session, the relay, and readings that say what they lack.

- Hooks did not start on an Intel Mac: Homebrew's tools were looked for under
  `/opt/homebrew` only. `req_path` in `scripts/requirements.sh` now takes the
  prefix of the `brew` on the path and otherwise looks under both
  `/opt/homebrew` and `/usr/local`.
- Codex fast mode was on for every review pass, which the owner never chose.
  It is now one setup question, off by default (`--codex-fast`,
  `--no-codex-fast`), saved as `codexFast` in `.claude/commandeck.json`; a
  project set up before has no answer and is off. Off is off: the pass and a
  launched Codex seat name the normal tier on their own command line
  (`-c service_tier=default`), and your Codex config is never edited.
- Setup creates the project's Orca run, or prints the one command when Orca
  does not answer, and ends with the list of project files it created or
  changed, each marked to commit or not.
- A relay chosen at setup had no worktree and no pane. Setup now creates the
  `Chief-of-Staff` worktree and opens its pane under the stored name; where it
  cannot, it ends with the exact steps. It says plainly that the session in
  the main checkout is not the relay, and so does the orchestrator's start-up
  text, in one line that names where the relay pane is or how to make it.
- New check `ci/version-check.sh`: it fails when a plugin file changed against
  main and the version in `.claude-plugin/plugin.json` did not. Docs and `ci/`
  do not count. The rule for the number is in `CONTRIBUTING.md`.
- The dashboard listed no issues for a brief whose issues sat under a
  sub-heading or in a section of their own. One reader,
  `scripts/brief-issues.sh`, now serves the dashboard and the launch dry run;
  an item with no issue number is listed as a line of its own;
  `templates/_batch-brief-template.md` starts a batch brief with "The issues",
  and the dry run says so when a brief names no work item.
- Usage and cost readings. A refused usage check now waits longer after each
  refusal in a row, an hour at most and never less than the service's
  `Retry-After`, which is read as seconds or as a date; the card says when the
  next try is. The limit panel keeps the day's cost when the usage reading is
  refused. A model with no price no longer hides what is left out: the total
  is marked partial, with the count of requests and the names of the models.
  A merged build writes its Builder's row to the token ledger, which nothing
  wrote before.

## 0.2.0 -- 2026-10-13

The version is 0.2.0: the second part rises for new behaviour, the third for
fixes. It is written in `.claude-plugin/plugin.json` and the README's badge.

The requirements of 2026-10-14.

- Set-up named one missing tool at a time and told the owner to reorder
  `PATH` in a shell start file. Now one list, in `scripts/requirements.sh`, is
  read by `setup.sh`, `doctor.sh` and the Mac preflight in `paths.sh`; the three kept lists that did not agree. One
  check names everything missing in two groups: "can install", with the one
  `brew install` or `sudo apt-get install -y` command, and "yours to do"
  (Orca, Homebrew itself, `gh auth login`, the Codex CLI). `setup.sh
  --install-missing` runs the printed commands and no other, then checks
  again; without the flag nothing is installed. `gh` and its sign-in are now
  checked. New test: `scripts/__tests__/setup-requirements.test.sh`.
- On a Mac whose first `bash` is the system's 3.2, hooks that do not parse
  under it failed, and a failed hook blocked every command. Every hook is now
  started through `hooks/lib/run-hook.sh`, plain `sh`, which finds a Bash 4
  or newer and runs the hook under it with its input untouched and, on a Mac,
  Homebrew's GNU tools ahead of the system's on its `PATH`; with none it
  prints one line and exits 0. A script started by Bash 3.2 starts itself
  again under Homebrew's Bash, once, with its arguments and input. CI has a
  macOS job for both. New test: `hooks/__tests__/run-hook.test.sh`.
- The Mac app ships Orca's command as `orca`, with no `orca-ide`. Set-up now
  offers the link, as the exact `ln -s` command, when the `orca` it finds
  really is Orca's, and otherwise names Orca and its releases page.
- The user settings file can carry its own `env.PATH`, which replaces the
  shell's inside every session. The check now reads both: a tool on one and
  not the other is named in one plain line, and the `orca-ide` link goes into
  a folder on the PATH a session gets. The settings file is never edited.
- `/commandeck:setup` passes what the owner types exactly as typed; it asks
  one fixed question before installing; and its first command is a probe, so
  a host project's own guard that refuses `orca-ide` is named before any
  question, and never worked round.

The setup questions of 2026-10-13.

- `/commandeck:setup` sent four questions in one call, one of them free
  text, and a refused call was read as "none". Now only fixed choices go
  through the question tool, each with a header of 12 characters or fewer and
  two to four options, at most four per call; names and commands are asked in
  plain text, and a refused call is asked again in plain text. New test:
  `scripts/__tests__/setup-skill-questions.test.sh`.

The public-release files of 2026-10-13.

- `SECURITY.md`, `CONTRIBUTING.md` and two issue templates (bug report,
  feature request) are new. CI is hardened: `actions/checkout` is pinned to a
  commit id, the workflow's token is `contents: read`, and the runner is
  `ubuntu-24.04`.

The README of 2026-10-13.

- `README.md` is rewritten from the plugin's files. New or longer: the first
  build walked through with the scripts' own output, review passes by build
  size, the hooks by group and which tier each is in, the Chief of Staff and
  its watchers, the decision ledger and the ruling log, cost control,
  checkpoints and resume, the dashboard, the build review, `/test-audit`,
  and the rows `scripts/proof-run.sh` printed. Corrected: a first pass is
  one reviewer under 200 changed lines; set-up stores the Chief of Staff's
  name and does not open its pane; `perl` is needed; the Builder model
  choices.

The carry-over of 2026-10-13.

- `builder-launch.sh --small` is main's word that a build is expected under
  200 changed lines: the Builder starts with no advisor and its brief says so,
  unless the launch is `--risky`, which keeps the advisor at any size.
  `--model <alias> --reason '<one line>'` puts one Builder launch on another
  model routing names, and logs the pick with its reason in
  `.claude/routing-log` (kept out of git by set-up). A tooling build under 200
  lines is launched `--small` on `--model sonnet`; a risky one stays on the
  configured model.
- `/test-audit` prices a split file's part by its real bytes (the listing
  stage returns each block's byte offset), so a part that holds the long lines
  is cut further or listed too large; the validator prices opening it the same
  way. Its coverage check also names a list no finished batch owns, reads an
  id given twice as wrong, and tells the validator to read every list.
- A finding on a GO report counts as resolved only by a word in its title or
  its reason, never by one in its last field, the failing command.
- Two old test fixtures hold made-up text: a sentence about a product and a
  home network address (now 192.0.2.20, a documentation range).
- `/test-audit` ends with one more stage, a Sonnet agent that checks the
  finished audit: that every test file was audited, that the counts agree,
  which files hit the five-note cap, which notes are plain facts (those
  become findings) and what the audit missed. It opens few test files whole
  and lists every one it did not open. When the stage fails, the audit's
  result still comes back, with one line saying the report is unchecked.
- A build's first pass is one reviewer, told all three angles, when the
  commit it reads is under 200 changed lines (insertions plus deletions
  against main, `.claude/briefs/` left out) and main did not launch the
  build with `--risky`; otherwise three reviewers, as before. A file git
  gives no line count for, or a build main's checkout holds no launch brief
  for, keeps three. The pass prints which rule chose the count and the round
  file keeps the line; the merge counts again and refuses a one-reviewer
  first pass the rule did not allow.
  Whether a launch was risky is read from the brief the launcher keeps in
  main's checkout, which is trusted as it already is for the stated limits:
  a Builder that edits that copy is not caught.
- The build review shows the build's lines changed beside the pass list
  and keeps the number in `result.json` as `lines_changed`.

The test audit and the fixes of 2026-10-13.

- `/test-audit <scope dir...> [basic|full] [N agents]` in a project where set-up has
  run: agents read the project's tests against its code and write a report
  of what is redundant, slow or missing. Report only: it changes no test.
  Set-up writes `.claude/workflows/test-audit.js` (git does not see it) and
  turns on `"enableWorkflows": true` in the project's `.claude/settings.json`
  unless the owner has set it; uninstall takes both back. A project with no
  recorded test runs gets no timing figures, and its token figures are a
  guide measured in one repository.
- No pane the plugin starts is refused the Workflow tool any longer.
- A Builder may be Opus advised by Opus, and `--builder-advisor none` (or
  `"advisor": "none"` in `.claude/commandeck.json`) starts it with no
  advisor.
- The Builder brief: a fix round re-runs only the test files it touched, the
  one whole run goes beside the closing pass, and a second variant of a
  fixed finding is fixed as a class with a short note to main, not a
  question that waits.
- A reviewer's finding line ends with the exact failing input or command,
  and a finding it cannot give one for is left out. The issue filed for a
  finding left open carries that command. Update the plugin
  between builds: a build whose earlier passes ran under the earlier prompt
  is refused, at its next pass and at the merge, and goes on only as a new
  unit (a new worktree made from its branch), reviewed from pass 1.
- The relay's inbox watcher keeps its place and its held notes in ONE file
  under a lock, so two watchers never show a note twice or lose a held one.
- A merge whose clean-up fails after the commit says MERGED, names the
  failed step and still ends with the NOT FILED lines and their command;
  it exits 4 when a finding has no issue, else 1.
- Inside a linked worktree `COMMANDECK_MAIN` and `COMMANDECK_WORKSPACES` are
  no longer followed as given: the project is the one git says the worktree
  belongs to (`scripts/project-main.sh` holds the rule and its one
  exception, a stand-in project under the system's temp folder).

The tooling sync of 2026-10-13.

- The relay pane's inbox watcher wakes for every note the orchestrator's
  pane sends by hand, whatever its subject; script traffic under that pane's
  name and worker reports still do not wake it. A note whose subject starts
  `FYI` is held and shown with the next note that does wake it.
- A merge files each finding left open as an issue (`file-open-findings.sh`;
  needs the `gh` CLI logged in and a GitHub remote). Without them the merge
  still lands, says NOT FILED with the command to run again, and exits 4;
  the merge queue goes on past a 4 and ends 4.
- The merge's build review opens no tab; a flagged build is still told to
  the relay pane.
- git-safety reads a quoted `git` word and a command in backticks as the
  commands they are; the search rule follows a substitution inside another
  and a search inside a subshell; an edit that would leave a hook script
  unparseable is refused.
- The dashboard colours a build's steps by how they ended (a NO-GO is never
  green), a panel can be dragged to any height, a stopped helper's open call
  no longer reads as stuck, and an evidence file headed "Item N" counts.
- The Builder brief: no advisor consult before any review pass, a failed
  consult is retried once, helper answers and long output are capped, one
  `Ponytail:` line per batch item.
- A review pass is handed the build's stated limits, read from main's
  checkout only: the launcher keeps a copy of the brief there
  (`.claude/briefs/<unit>-builder-brief.md`).
- No ruling id of the source project is left in the tree, and the leak test
  fails on one.

The close-out before the first release.

- The licence is Apache-2.0 (`LICENSE`), and `NOTICE` names the bundled
  skill, what the plugin runs on and each optional add-on with its licence.
  Both manifests name the author, the repository and the licence.
- The leak test allows two exact texts and nothing near them: the
  repository's own address anywhere, and the owner's name in `LICENSE`,
  `NOTICE` and the two manifests. In a checkout it searches git's own list
  of files, so an ignore rule hides no tracked file.
- A build's working papers under `.claude/briefs` are no longer tracked or
  exempt from the leak test; `.gitignore` keeps them out.
- The dashboard counts the project's open GitHub issues labelled `P1`, as
  `gh` resolves the repository from the project's checkout. A count above
  zero keeps the needs panel shown; a count `gh` could not give within 8
  seconds reads "Not measured", never 0.
- `uninstall.sh --delete-data` also removes the project's finished-builds
  record, `~/.commandeck/builds/<project>.jsonl`.

The rest of the workflow. The plugin now wires itself into Claude Code and
into a project, and takes itself back out.

- Hooks registered in `hooks/hooks.json`, in two tiers: the default tier
  stops lost work and wrong commits; the strict tier (a setup answer) also
  holds a session to searching before reading and one test run per change.
- The orchestrator's flow: Builder launch with a hard stop for risky work,
  review passes on Codex or on a second Claude, a local squash merge that
  takes only a batch whose last pass ended GO.
- A Chief-of-Staff relay pane, and a dashboard that shows every registered
  project on one local page.
- Codex runs the same hooks through `hooks/codex-dispatch.sh`.
- `setup`, `doctor`, `update` and `uninstall`, as skills and as scripts.
  Setup records every file before it changes it; uninstall puts each back.
  The project's config carries `version: 1`; there is no migration code.
- A project whose model holds 200K (`standardContext`) checkpoints and
  restarts at 150K instead of 200K.
- `scripts/proof-run.sh` prints the numbers a release is compared by.
- A script now works for the project it is run in, not the folder the plugin
  sits in, so one installed copy serves every project.
- Each project keeps its own Orca run in its scratch folder; `board.sh`
  records it from main's own pane. Orca's machine-wide `current-run` file is
  no longer read, so two projects on one machine do not follow one run.
- Setup and the doctor ask for Python 3.11 or newer (the Codex side reads
  `config.toml` with `tomllib`).
- `setup.sh --no-dashboard` is remembered for the project; `--dashboard`
  takes it back.
- The dashboard is served by `scripts/dashboard_serve.py`, which answers its
  own page only: another site's page cannot read the snapshot.
- Review is three passes: a first pass by three reviewers, narrowed passes on
  the fixes, and a closing pass. A closing pass that leaves only P2 or P3
  findings still merges and prints each as open; any P0 or P1 refuses.
- The merge check runs on a copy of the commit to be made, so files of yours
  lying in the main checkout neither stop a merge nor take part in its check.
- A build review skill (`skills/worktreereview`): a page of timings and cost
  per build, made at merge.
- The dashboard is rebuilt: more panels, a price table that knows Codex's
  prices, Builder alerts, a layout you can save.
- The dashboard lists a project's finished builds, drawn as running ones are;
  a build you clear stays cleared in every browser. The needs panel carries
  your own name, and stays in view while a finished build has a P1 open.
- `setup.sh --hosts <name>[,<name>]` lets the dashboard answer under another
  name of this machine; the list is closed without it, and the doctor names
  the command.
- Setup installs the ponytail skill (never over one you have) and prints a
  command and a cost for every add-on. `setup.sh --status-line '<command>'`
  sets a status line and records yours; uninstall puts it back.
- The doctor reports which add-on servers (`serena`, `codebase-memory`) are
  present.
- The relay pane may run its watcher scripts and the decision script without
  a permission prompt.
- The repository no longer carries a second copy of the scripts and hooks
  under `.claude/`; it runs on the plugin tree itself.

## 0.1.0 -- 2026-10-11

The skeleton. Nothing is wired into Claude Code yet: the plugin installs, and
the scripts run from a checkout of this repository.

- Plugin manifest and a one-plugin marketplace, so the repository installs
  from a local path.
- `config/routing.json` with four roles (orchestrator, builder,
  codex-reviewer, claude-reviewer), model families only.
- The Builder flow and the orchestrator's scripts and hooks, copied from the
  project this workflow was built in and renamed for this one.
- `ci/leak-test.sh` and a GitHub Actions workflow that runs it and the shell
  tests on every push and pull request.

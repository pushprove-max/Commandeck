# Changelog

## 0.12.0 -- 2026-10-17

- Plan before build: `plan-tier.sh <batch-brief>` answers "Write a plan first?" with No plan, Plan + judge or Panel,
  from the triggers in `config/plan-triggers.tsv` (or the project's own `.claude/plan-triggers.tsv`), going one tier
  up when unsure. Plan seats (`plan-author`, the judges) run in a planning worktree `<unit>-plan` cut from main, with
  one judge round and one revision. A plan is never a build order.
- `builder-launch.sh` closes the unit's `<unit>-plan` worktree and its panes once the Builder's pane is open. It keeps
  the worktree, with one REFUSED line, when it holds a file that is not identical on local main or a pane does not
  close. A rejected plan's worktree closes by hand with `bash scripts/plan-worktree-close.sh <unit>` (`--dry-run`
  removes nothing). An unreadable, empty or error pane list counts as "panes not closed", never as "no panes".
- The merge check (`testCommand`) is now `bash scripts/run-shell-tests.sh --changed`: it runs only the shell tests the
  change touches, and each touched script's or hook's same-name test. The whole suite stays
  `bash scripts/run-shell-tests.sh`, and CI still runs it on every push.
- Removed the three slowest shell tests: builder-launch.test.sh, suite-rerun-guard.test.sh and merge-unit-local.test.sh.

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

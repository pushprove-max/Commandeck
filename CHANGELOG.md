# Changelog

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

# Changelog

## Unreleased

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

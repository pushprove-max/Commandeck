<h1 align="center">Commandeck</h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.7.2-111111?style=flat-square" alt="Version 0.7.2">
  <img src="https://img.shields.io/badge/license-Apache--2.0-111111?style=flat-square" alt="Apache-2.0 license">
  <img src="https://img.shields.io/badge/runs%20on-Claude%20Code%20%2B%20Orca-111111?style=flat-square" alt="Runs on Claude Code and Orca">
</p>

---

Commandeck is a Claude Code plugin that runs on
[Orca](https://github.com/stablyai/orca). It splits agent work into three
jobs. One Claude session in your main checkout, the orchestrator, plans with
you, launches builds and merges them; it does not write the code. Each batch
of work gets a Builder, a second session in its own git worktree. A reviewer
on another model reads what the Builder committed, and the merge script takes
a branch only when it can find that reviewer's verdict for the commit being
merged: a `VERDICT: GO`, or a closing pass that left nothing above P2.

## What you need

| Need | For |
|---|---|
| [Orca](https://github.com/stablyai/orca), and its command under the name `orca-ide` on `PATH` | worktrees and panes |
| Claude Code | every session |
| git | worktrees, the merge |
| GitHub CLI (`gh`), signed in | the issues a merge files for findings left open, and the dashboard |
| `jq`, `perl`, Python 3.11 or newer, Bash 4 or newer | the scripts and the hooks |
| GNU `sed`, `stat`, `date`, `readlink`, `grep`, `realpath`, `timeout`, `sha1sum` and `sha256sum`; `flock` | the scripts |
| Codex CLI and the `openai-codex` Claude Code plugin, both signed in | the `claude-openai` profile only: its review passes run on Codex |

It runs on macOS and Linux, and on Windows through WSL. The table is
the list in `scripts/requirements.sh`, the one set-up, `doctor.sh` and the scripts'
own preflight read. `/commandeck:setup` checks all of it at once and names
what is missing in two groups. What a package manager supplies comes with the
one command for your machine (`brew install ...` on macOS, `sudo apt-get
install -y ...` on Linux), and set-up runs that command when you say yes, and
nothing without it. The rest is yours to do, each with its step: Orca,
Homebrew itself, `gh auth login`, the Codex CLI.

Orca is a desktop app you install yourself, from
[its releases page](https://github.com/stablyai/orca/releases): the `.dmg` for
your chip on a Mac, the `orca-ide` `.deb`, `.rpm` or AppImage on Linux. The
Linux packages name its command `orca-ide`. The Mac app names it `orca` and
puts no `orca-ide` anywhere, so on a Mac set-up offers to link `orca-ide` to
the app's own command, in a folder of yours that is already on `PATH`.
Homebrew's `orca` is another program.

On macOS, Bash 4+ and the GNU tools come from Homebrew (`bash`, `coreutils`,
`gnu-sed`, `grep`, `flock`). The scripts look in Homebrew's folders
themselves, a script the Mac's own Bash 3.2 started carries on under
Homebrew's, and the hooks are started through a launcher that finds a Bash 4
or newer, so your shell's start file needs no edit. Until that Bash is there
the hooks do not run: each says so in one line and blocks nothing.

If your `~/.claude/settings.json` sets its own `env.PATH`, that is the `PATH`
every session and hook gets, in place of your shell's. Set-up checks both: a
tool that is on one and not the other is named in one line, and the `orca-ide`
link goes into a folder on the session's. Set-up never edits that setting.

GitHub is the only git host, and a project needs a GitHub remote to get a
dashboard. Everything runs on one machine. Nothing here pushes: a merge is a
local squash commit on `main`, and pushing it is yours to do.

## Install

In Claude Code, as two separate prompts:

```
/plugin marketplace add pushprove-max/Commandeck
```
```
/plugin install commandeck@commandeck
```

Or from a terminal:

```bash
claude plugin marketplace add pushprove-max/Commandeck
claude plugin install commandeck@commandeck
```

Then, in each project, in a Claude Code session:

| Command | Does |
|---|---|
| `/commandeck:setup` | checks the requirements, asks its questions once, shows every change it would make (`setup.sh --plan`), and only on your Apply writes the project's config, the permission rules, the watcher job and the answers you chose. Every file it changes is recorded first, and a file of yours is copied beside it (`<file>.commandeck-bak-<date>`) |
| `/commandeck:doctor` | checks the wiring and changes nothing; each `FAIL` line ends with the command that fixes it |
| `/commandeck:update` | after `claude plugin update`: points everything at the plugin's new folder, runs the doctor, and puts the files back if it fails |
| `/commandeck:uninstall` | puts every file back as it was; the gathered data is kept unless you say delete |

The same four are scripts: `scripts/setup.sh`, `doctor.sh`, `update.sh` and
`uninstall.sh [--delete-data]`. They live in the plugin's own folder, where
Claude Code installed it, and not in your project. Setup's output ends with
a `check it: bash <path>/scripts/doctor.sh` line; the commands below call
that `<path>`, the folder that holds `scripts/`, `$PLUGIN`, and are run from
your project. Script names in the text are relative to it. Setup
never commits. When it wrote files that
every worktree needs, its output ends with the `git add` and `git commit`
line to run.

### What setup asks

Each question says what its choices do, offers the recommended one first
(a saved answer first on a rerun), and is asked only when it applies. While
setup asks, the picker guard's stray-keypress option is off.

| Question | Choices |
|---|---|
| Reviewer | `claude`: a second Claude on a different model family reviews each build. `claude-openai`: Codex reviews it (offered when the Codex CLI is ready) |
| Permissions | this project: the rules go in `.claude/settings.local.json`, which git never sees (they name this machine's plugin folder). Every project: in `~/.claude/settings.json`. A changed answer moves them |
| Your rules | asked when the project has a `CLAUDE.md` or `.claude/rules/`: merge (sessions leave out the plugin's rules yours already state word for word; for a rule that only says the same in other words, or disagrees, you choose keep mine, use the plugin's or keep both) or keep both |
| Your own startup files | asked each time for a project's own `AGENT_STARTUP.md` and `.claude/main-session.md`, which otherwise load instead of the plugin's: merge (the plugin's rules yours lack are added in a marked block), replace (sessions load the plugin's; yours stays on disk) or skip |
| Global rules, global CLAUDE.md | when `~/.claude/CLAUDE.md` exists: merge (only the rules it lacks), add as block, or skip; when it does not: install or skip. Your own text is never changed; uninstall takes out only the plugin's blocks |
| Builder model, context | Opus (the default) or Sonnet for less usage; every Builder runs at effort high with no advisor. 200K or a larger window |
| Relay | none, or a Chief of Staff pane with a name and one line on how it should sound |
| Dashboard | on for this machine only, off, or on plus another name it answers to (a tailnet's) |
| Merge check | the command that must pass before a merge, or none |
| Strict hooks | off or on (see [Hooks](#hooks)) |
| Ponytail | on (the skill is installed) or off |
| Prompt cache | recommended (`promptCacheTtl` 1 hour for main and Claude panes, `subagentPromptCacheTtl` 5 minutes, in `.claude/settings.json`; a value you set stays) or Claude Code's default (writes nothing) |
| Add-ons | any of serena, codebase-memory, agent-browser, or none (see [Add-ons](#add-ons)) |
| Review loop | defaults, keep saved, or tune: the most review rounds (no cap by default), whether a closing pass reads the whole branch (it runs by default), the small-build line for a one-reviewer first pass (200; off gives every first pass three reviewers), and when a finished build is flagged for a written review (30 minutes of Codex review, a third of the clock on tests or idle waits when they also pass 10 minutes, $30). Numbers are saved as typed; taking every default saves nothing |
| Codex fast, Codex model | with the Codex reviewer only: fast mode, offered when your Codex config allows it, and a model id when setup found none |

Then setup prints the plan, every file it would create or change with a
diff, and asks Apply, Change an answer, or Cancel. Its summary ends in three
parts: what it did, what needs you (a command it could not run, files to
commit), and what is optional, with how to change any answer later: run
`/commandeck:setup` again, or `setup.sh` with only that flag. It also creates
the project's Orca run, or prints the one command for it. Your own status
line is set with `--status-line` (uninstall puts the earlier one back).

## The first build

After setup, the Claude session in the project's main checkout is the
orchestrator. You tell it what you want in plain words. It writes a batch
brief with you (the items and how each will be judged done) and launches a
Builder:

```bash
bash "$PLUGIN/scripts/builder-launch.sh" add-csv-export .claude/briefs/add-csv-export-batch.md
```

You do not type that; the orchestrator does. The launcher makes a new Orca
worktree on local `main`, puts the rendered brief in it, opens one Builder
pane and prints one line:

```
seat=builder unit=add-csv-export handle=term_… task=task_… state=… record=…
```

The Builder builds the batch, then runs its own review passes with
`builder-codex-pass.sh` (or `builder-claude-pass.sh` in the `claude`
profile). Each pass commits the worktree first, so the reviewer reads exactly
one commit, and writes a round file from the reviewer's own session record.
The merge takes the verdict from the reviewer's session files and not from
the round file, so a round file written by hand merges nothing. That stops a
Builder from passing itself by mistake. The session files belong to the same
user, so it does not stop an agent that sets out to forge one. A pass prints:

```
add-csv-export-r1-reports.md: VERDICT: GO (adversarial pass on 3f9c2a1, …)
```

A watcher service, `main-watch.sh`, installed by setup, posts a message to
the orchestrator when the Builder's pane stops. The orchestrator then runs
the merge from the main checkout:

```bash
bash "$PLUGIN/scripts/merge-unit-local.sh" add-csv-export
```

```
STEP 1 preconditions: main=… worktree=… branch=add-csv-export
STEP 2 rebase: git -C … rebase main
STEP 4 size: 4 files changed, 212 insertions(+), 9 deletions(-)
STEP 4 merge: git merge --squash add-csv-export; npm test; git commit -m …
STEP 5 cleanup: orca-ide terminal close --worktree … --all; orca-ide worktree remove --worktree … --force
DONE unit=add-csv-export merged=local sha=8d41e07; …; nothing was pushed
```

Those are some of the lines the scripts print, with example values filled
in. Between
steps 2 and 4 the merge looks up the reviewer's session and refuses when the
proof is missing or older than the branch tip. It runs your test command once
on a copy of the squashed tree before it commits, and a red run undoes the
squash. Then it closes the unit's panes and removes the worktree. It does
not write the build review: that runs only when you ask for it.

`bash "$PLUGIN/scripts/board.sh"` prints the state of every worktree, seat and open
task at any point. `merge-unit-local.sh <unit> --dry-run` runs the checks and
merges nothing.

## Review passes

A build's first pass reads the whole branch. It is three reviewers at once,
one angle each, unless the commit is under 200 changed lines, or the number set at setup (insertions plus
deletions against `main`) and the build was not launched with `--risky`; then
it is one reviewer told all three angles. The pass prints which rule chose,
and the merge counts the lines again and refuses a one-reviewer first pass
the rule did not allow.

After that come narrowed passes, each reading only the changes since the last
one, until one ends `VERDICT: GO`. A closing pass then reads the whole branch
again. If the first pass ends GO and nothing is committed after it, that GO
merges and no closing pass is needed. A project that answered "none" to the
closing pass at setup merges the narrowed pass that ends GO, once narrowed
passes have read every commit after the first pass; one that set a round cap
has any pass numbered above it refused.

Each pass after the first prints the files and lines changed since the last
pass, and says so when no code line changed (only comments or blank lines). If
main's brief or rulings for the build changed since the last pass, a `review`
pass reads the whole branch as a closing pass does, so a part main added in a
fix round is reviewed with the rest. The Builder's evidence-file lines
`Different fix r<N>: <why>` and `Other cases checked r<N>: <which>` go into the
prompt of pass N.

Each pass is checked against the exact prompt it was sent, and so is every
earlier pass of the same worktree. A plugin update that changes the review
prompt's text (this plugin building itself is where that happens) therefore
refuses a build whose passes ran under the old text, at its next pass or at
its merge. This is expected, and it never gives a wrong GO. The refusal names
the way on: make a new unit from that branch and run its first pass; a GO
there with nothing committed after it merges.

Findings are graded P0 to P3. A P0 or P1 refuses the merge. A closing pass
that leaves only P2 or P3 findings still merges: the merge prints each one as
open and files a GitHub issue for it. If GitHub cannot be reached the merge
stands, the output lists what was not filed, and the exit code is 4.

A launch with `--risky` opens a design pane first. It writes a design note
that the Builder reads before it builds; running the same command again opens
the Builder. Every Builder runs with no advisor, a `--risky` one included. A
launch with `--small` says the batch is expected under 200 changed lines; it
also drops an advisor written into `config/routing.json`'s `roles.builder` by
hand. `--model <alias> --reason '<one line>'` puts one launch on
another allowed model.

`scripts/merge-queue.sh <unit> ...` merges several finished units in the
order given, one at a time, and stops at the first that does not merge, or
that merged and then failed a later step (exit code 3); it says which.

## Hooks

`hooks/` holds about forty scripts, registered in `hooks/hooks.json`. They
come in two tiers. The default tier is always on. The strict tier is a setup
answer (`"strictHooks": true` in `.claude/commandeck.json`). The hooks catch
honest mistakes. An agent that sets out to get round one can.

The default tier covers git, the orchestrator's lane and a few mistakes that
are expensive later:

- `git-safety.sh` refuses a force push, a remote branch deletion, `--mirror`
  and `git reset --hard`. It reads through quoting tricks such as `pu''sh`.
  It does not screen `eval` or a command held in a variable.
- `main-edit-guard.sh` blocks edits to project code in the main checkout, so
  the orchestrator hands code to a Builder. Everything under `.claude/`, docs
  and Markdown files stay editable there.
- `duplicate-agent-guard.sh` refuses a second agent pane in a worktree that
  already has a live one, and a new job sent to a pane whose agent is
  mid-turn.
- `dependency-addition-guard.sh` blocks a new npm dependency, whether it
  arrives by `npm install <pkg>` or by an edit to `package.json`, until you
  approve it. Approval is a prefix on the command:
  `COMMANDECK_DEP_APPROVED=1 npm install <pkg>`. It knows npm only.
- `literal-secret-warning.sh` warns when an edit assigns a quoted literal of
  eight characters or more to something named `password`, `secret`, `apiKey`,
  `token` or `credential`. It warns and lets the edit through, and it skips
  test files and env files.
- `agent-model-guard.sh` sets the model of helper agents. A helper call that
  names no model would inherit the orchestrator's, the most expensive one, so
  an unnamed Explore call runs on Haiku, an unnamed general-purpose or
  debugger call on Sonnet and any other unnamed call on Opus. It rewrites the
  call and never refuses one.
- `no-poll-loops.sh` stops the orchestrator from waiting in a `sleep` loop;
  it waits on Orca's inbox. A bare `orca orchestration check` with none of
  `--wait`, `--peek`, `--all`, `--ack` or `--terminal` is refused in every
  pane, and a worker's `sleep` loop is pointed at `run_in_background` or the
  Monitor tool.
- `worker-ask-guard.sh` stops a worker or reviewer
  from opening a question picker in its own pane, where nobody would see it.
- `write-existing-file-guard.sh` warns when an edit mostly restates lines
  it replaces.

The strict tier adds the hooks that hold a session to cheaper habits and
catch weak tests:

- `test-skip-only-blocker.sh` blocks an edit that adds `.only`, `.skip`,
  `xit`, `fit` or `it.todo` to a test.
- `suite-rerun-guard.sh` blocks the same test or type-check command on an
  unchanged tree within 30 minutes, with or without commands chained on;
  edits under `.claude/briefs/` leave the tree unchanged. Prefix `RERUN=1` to
  run it anyway. It recognises npm's test and typecheck scripts, `tsc` and
  `vitest`.
- `edit-content-tripwires.sh` blocks new CRLF line endings, deferred-work
  markers, comments that suppress TypeScript and `eslint-disable`.
  `file-size-cop.sh` holds a `.ts` file to 500 lines and a `.tsx` file to
  400. `bash-guardrails.sh` caps the heap of Node's test runner at 4 GB.
- A handful only advise: three turns in a row with one read-only call each,
  the fifth file of one kind opened from one folder, a written file that git
  ignores, a new test file for a module that already has one.

A Builder's worktree gets two more: a guard that sends long runs of searches
to a Haiku subagent, and an event log of subagent and review-pass starts and
stops.

In the `claude-openai` profile the same hooks run for Codex. Setup puts one
entry per event in Codex's `hooks.json`, pointing at
`hooks/codex-dispatch.sh`, which reads the plugin's own `hooks.json` and
turns each file of a Codex patch into the edit payload the hooks were written
for. They run only in a project that is set up for the plugin and trusted by
Codex. Hooks that depend on a Claude-only tool (the serena lookups, the pane
budget) are marked `# codex: skip` and do not run there.

Several of these know only npm and TypeScript. In another stack they stay
silent.

## Chief of Staff

The Chief of Staff is a separate Claude pane that relays between you and the
orchestrator, so questions for you arrive in one place while builds run. It
reads no code and never answers for you.

When you choose one, setup creates an Orca worktree named `Chief-of-Staff`,
gives it its relay-only settings and opens the pane under the stored name.
Where it cannot (Orca does not answer, or the worktree is already there), it
ends with the exact commands left to run. The session in the main checkout is
the orchestrator and never the relay; its start-up text says where the relay
pane is, or that none exists yet. Without one, the orchestrator asks you
directly.

The pane keeps four watchers running in the background. Each one prints what
it found and exits, which wakes the pane:

| Watcher | Wakes the pane when |
|---|---|
| `cos-watch-inbox.sh` | the orchestrator sends it a message (checked every 20 s). A subject starting `FYI` is held and shown with the next message that does wake it |
| `cos-watch-decisions.sh` | a decision in the ledger is open and you have not been asked yet (every 20 s) |
| `cos-watch-alerts.sh` | the dashboard raises an alert for this project or the machine (every 60 s) |
| `cos-watch-limit.sh [<percent>]` | the 7-day usage limit reaches the threshold, 90% by default, and again for each whole percent above it |

A Stop hook keeps the pane from ending a turn with no inbox watcher alive.
`scripts/cos-tell.sh <text>` sends text to the pane from a terminal, which is
how a dictation shortcut reaches it. `scripts/cos-tell.sh --note <subject>
<body>` is the orchestrator's note to it: stored in the orchestrator's run,
where the inbox watcher finds it even if the pane was busy, and it exits 1
when Orca does not confirm the note was stored.

The decision ledger is `.claude/metrics/decisions.jsonl` in the main
checkout. Every question the orchestrator puts to you becomes a row, written
by a hook, and the dashboard's "Needs the owner" card reads it.
`scripts/decision.sh` has `add`, `check`, `answer`, `reopen` and `list`. A
question that is still open, or was answered in the last 24 hours, cannot be
asked again without `--reask` and a line on what is new.

The ruling log is `~/.claude/rulings/<project>.jsonl`. A hook appends one row
for every answer you give, by picker or by prompt, with the time it happened
and an id. Agents cite that id when they write "the owner decided X", so a
decision can be traced to your words. An answer that comes back in under two
seconds is marked suspect: it may be text another pane typed into the open
picker.

## Cost control

- Startup size. Claude Code shows the model only a 2 KB preview of a session
  start that prints more than 10,240 bytes. `scripts/startup-size.sh
  [--role main|worker|builder|chief-of-staff] [--per-prompt]` measures what
  each seat's hooks really print and exits 1 over the limit.
- The clear line. Past 200K tokens of context (150K with
  `--standard-context`) the orchestrator gets a line on every prompt telling
  it to checkpoint. See [Checkpoints](#checkpoints-resume-and-handoff).
- The pane budget (strict tier). A worker pane past 450,000 tokens of context
  (`config/pane-budget.json`) may not edit or run commands until it has
  written a handoff file with its decisions, open findings, current commit
  and test evidence.
- The cache check. `scripts/builder-cache-check.sh <worktree> [session-id]`
  reads a Builder's transcripts and fails unless its main thread wrote only
  1-hour prompt cache and its subagents only 5-minute cache.
- The price of each build. The build review prices every request at list
  price from one table in `scripts/dashboard_limit.py` and flags a build over
  $30. These are list-price equivalents and a subscription plan bills
  differently. A model with no list price on file is shown as unpriced,
  never as $0.
  `scripts/unit-cost.sh <unit>` prints the same build as turns, tool calls
  and tokens per session.
- Helper usage. `scripts/subagent-usage.sh` records one row per finished
  subagent run (type, model, tokens) in
  `.claude/metrics/subagent-usage.jsonl`. `scripts/seat-tokens.sh` totals
  tokens per unit and per role.
- The 7-day limit. The dashboard reads your account's usage and shows the
  7-day limit for Claude and Codex; the limit watcher above tells you at
  90%.

## Checkpoints, resume and handoff

The orchestrator's session never compacts. Past the clear line a Stop hook
holds its turn until it has written a checkpoint to
`~/.claude/checkpoints/<session id>.md` from `templates/checkpoint.md`: the
goal, the live units, what it is waiting on, the queue, what was ruled out
and how to resume. `scripts/state-snapshot.sh` fills in the mechanical
fields. With a checkpoint under 30 minutes old the hook restarts the
orchestrator in a fresh Orca pane and closes the old one.

Claude Code (2.1.299 and later) compacts an idle session by itself: past
200K tokens and about 54 idle minutes (`CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`
moves the line). That suits the relay and Builder panes, and the plugin
ships no compactor of its own. The orchestrator restarts at the clear line
before it can sit idle that large; if a restart fails, it can still be
compacted, unless `"idleCompaction": false` is in the main checkout's
`.claude/settings.local.json`.

The new session starts with that checkpoint, the board, its run binding and
your last eight prompts word for word already in context, under the same
10,240-byte limit. A check compares the new checkpoint with the one the
session resumed from and blocks the restart when an open item was dropped
without a reason.

`/commandeck:handoff` does the same checkpoint and restart on demand, below
the line. You have to type it; the model cannot invoke it.

Outside Orca the hook cannot restart the pane. It says so and asks you to
type `/clear`, and the new session does not get the resume block.

## Dashboard, build review and test audit

The dashboard is one local page for all your projects, with a bar to switch
between them. A background job collects its data every 60 seconds with no
model call, and the page reloads every 15. Each project's view shows alerts,
builds in progress, decisions waiting on you, `main` against its remote,
every worktree by stage, the 7-day limit, tokens per role over 7 days, recent
hook blocks and the Chief of Staff's inbox. Three panels show GitHub work:
open pull requests with their checks, open issues by milestone with the
Builder holding each, and the commits the next push of `main` would send.
They read `gh` (read-only, every 5 minutes) and git. Without `gh`, or signed
out, each says so and the rest of the page still works. An issue number links
to the issue on GitHub.

It serves plain HTTP on `127.0.0.1`, on the first free port from 8791, and
setup prints the address. It has no login. On the loopback bind it answers
403 to any other host name; `--bind` and `--hosts` at setup open it to your
own network, and it still has no login there.

The build review runs only when you ask for it:
`/commandeck:worktreereview <unit>`, for a merged build or one still running.
The merge does not run it. It makes one HTML page per build under
`~/.commandeck/reviews/`, with the session's notes on what to learn from it.
It shows where the time went stage by stage, every review pass with its full
findings and lines changed, tokens and list-price cost by model, and time
spent waiting. The page flags a build with over 30 minutes of review, over
$30, or over a third of its clock (and over 10 minutes) on tests or idle
waits; that flag names the largest single command. A wait on a review pass
run outside the Builder's session, or on a review tool that was down, is
shown on its own and flags nothing. A lesson that proposes a change becomes
a draft issue, and only the drafts you approve are filed. It reads logs
only, so it works after the worktree is gone.

`/test-audit <scope dir...> [basic|full] [N agents]` has agents read a
folder's tests against its code and report what is redundant, slow or unable
to fail, and in `full` mode what is missing. Up to 16 Haiku agents read in parallel (4 by default), and a
last Sonnet stage checks the audit itself: that every file was read and that
the counts agree. It changes no file and runs no test. It stops above 200
test files, so give it a folder and not the repository. It is a Claude Code
workflow, which setup installs in the project and turns on.

## Numbers

`scripts/proof-run.sh` builds a throwaway machine in a temp folder (an empty
home that another tool has already written to, a small Node project, stubs
for Orca, `claude` and `codex`), runs setup, the scripted steps of one unit
and uninstall for each profile, and prints one row per measure. No model
runs. From version 0.1.0, run on 2026-10-13, the same for both profiles
unless noted:

| Measure | Result |
|---|---|
| Startup bytes, orchestrator | 7437 (limit 10240) |
| Startup bytes, Builder | 4037 |
| Startup bytes, worker | 3746 |
| Startup bytes, Chief of Staff | 2064 |
| Hook cost over the scripted unit | 9 hooks, 29 fires, 2 blocks; slowest p95 126 ms (`claude`), 119 ms (`claude-openai`) |
| The 150K clear line of `--standard-context` | fires on a 160K transcript |
| Another tool's hooks, settings and job file while installed | identical |
| After uninstall, data kept | identical but for the kept data (19 paths) |
| After uninstall, data deleted | identical |

The timings vary from run to run and machine to machine. Tokens per role,
cache hit rate and passes to GO need a real build, so the script prints them
as "not measured" with the command that measures each. To reproduce, from a
clone of this repository:

```bash
bash scripts/proof-run.sh                      # both profiles
bash scripts/proof-run.sh --profile claude     # one
```

## Add-ons

Setup asks which add-ons to install, in one question that takes several
answers. Each one you pick is installed for the project's main checkout by
its command in `config/addons.tsv`, and setup reports it as installed or, with
the command to run, as failed. One you do not pick installs nothing; setup
prints its command and what it costs you. Picking serena also turns on the
hooks that use it (`--serena`). The [Ponytail](https://github.com/DietrichGebert/ponytail)
skill (`templates/ponytail`) is its own question, on by default, and left
alone when you already have it.

| Add-on | What it adds | What it costs |
|---|---|---|
| [serena](https://github.com/oraios/serena) | symbol lookup for code | one language-server process per project |
| [codebase-memory](https://github.com/DeusData/codebase-memory-mcp) | a graph of the whole repository | one background indexer; its tool list rides in every session |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | a browser the agent can drive | a browser download of a few hundred MB |
| [ponytail](https://github.com/DietrichGebert/ponytail), the full plugin | its rules at every session start | about 1 KB per session |
| [ui-themes](https://github.com/yugal1107/ui-themes) | UI theme skills | loaded only when asked for |
| [mattpocock/skills](https://github.com/mattpocock/skills) | a set of engineering skills | one line per skill in every session's skill list |

Who wrote each one, and under what licence, is in [`NOTICE`](NOTICE).

## Layout

| Path | Holds |
|---|---|
| `.claude-plugin/` | the plugin manifest and a one-plugin marketplace |
| `config/routing.json` | each role's agent, model family and effort |
| `scripts/` | the Builder flow and the orchestrator's tools; `paths.sh` is the one home of every path |
| `hooks/` | the hook scripts and `hooks.json`, which registers them |
| `dashboard/` | the dashboard's page; `scripts/dashboard.sh` collects its data |
| `templates/`, `skills/` | the brief, checkpoint and Codex templates and the test-audit workflow; the setup, doctor, update, uninstall, handoff and build review skills |
| `ci/` | the leak test and its word list |

State lives under `~/.commandeck/`; the record of what setup changed is in
`~/.commandeck/install/`. Worktrees go under `~/orca/workspaces/<project>/`.
Environment overrides start with `COMMANDECK_`; `scripts/paths.sh` lists the
path ones.

## Tests

From a clone of this repository:

```bash
bash scripts/run-shell-tests.sh    # every shell self-test
bash ci/leak-test.sh               # no name from the source project in the tree
bash scripts/proof-run.sh          # the numbers above
```

## Support

Best effort, no guaranteed response time. Report every problem in one place:
the Issues tab of this repository. Include the output of the command that
failed and of `claude --version`.

## Licence

[Apache-2.0](LICENSE). Third-party work and what each add-on is licensed
under: [`NOTICE`](NOTICE). What each version added: [`CHANGELOG.md`](CHANGELOG.md).

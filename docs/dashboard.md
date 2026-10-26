# Dashboard, build review and test audit

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

The dashboard is one local page for all your projects, with a bar to switch
between them. A background job waits 60 seconds between collections, with no
model call; collection time adds to that interval. The page refreshes its
data every 15 seconds. Each project's view shows alerts,
builds in progress, decisions waiting on you, `main` against its remote,
every worktree by stage, a unit's planning as its Planning stage, seat by seat,
counted in its build's cost, the 7-day limit, tokens per role over 7 days, recent
hook blocks and the Chief of Staff's inbox. Three panels show GitHub work:
open pull requests with their checks, open issues by milestone with the
Builder holding each, and the commits the next push of `main` would send.
They read `gh` (read-only, every 5 minutes) and git. Without `gh`, or signed
out, each says so and the rest of the page still works. An issue number links
to the issue on GitHub.
A planning card lists every plan seat with its model, effort and state;
`COMMANDECK_CODEX_REVIEW_HOME` (default `~/.codex-review`) names the review
Codex home whose spend counts.

It serves plain HTTP on `127.0.0.1`, on the first available port in 8791–8890 unless you set a port, and
setup prints the address. On the loopback bind it has no login and answers
403 to any other host name. `--bind` and `--hosts` at setup open it to your
own network, and there it serves HTTPS only, behind a login (below). Network
mode also accepts the machine's own names and IP addresses; the hosts list is
not an authentication mechanism.

The login is on only for a network bind. One user, one password of at least 8
characters, stored as an scrypt hash in `~/.commandeck/dashboard-auth.json`
(mode 600, outside the served folder; `COMMANDECK_DASHBOARD_AUTH` moves it).
The certificate is self-signed, made once at install, in
`~/.commandeck/dashboard-tls/`; your browser asks you to trust it the first
time. A page without a login is sent to `/login`; a write is refused with 401.
Five wrong passwords in 15 minutes lock the login for 15 minutes. A session
lasts 12 hours and ends when the dashboard restarts; "Trust this device" keeps
a login for a year, across restarts. Once logged in, any device can answer a
question, retry a send, save the layout and restart the collector.

```bash
python3 "$PLUGIN/scripts/dashboard_serve.py" set-password <user>   # asked twice; ends every session, keeps devices
python3 "$PLUGIN/scripts/dashboard_serve.py" devices               # id, label, created
python3 "$PLUGIN/scripts/dashboard_serve.py" revoke <id>|all       # all: every device and every session
python3 "$PLUGIN/scripts/dashboard_serve.py" make-cert --force     # a new certificate
```

`dashboard.sh --install` on a network bind exits 5 until a password is stored.

The build review runs only when you ask for it, for a merged build or one
still running:

```text
/commandeck:worktreereview add-csv-export
```
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

The test-audit workflow has agents read a
folder's tests against its code and report what is redundant, slow or unable
to fail, and in `full` mode what is missing. Up to 16 Haiku agents read in parallel (4 by default), and a
last Sonnet stage checks the audit itself: that every file was read and that
the counts agree. It changes no repository file and runs no test; it writes reports to scratch. It stops above 200
test files, so give it a folder and not the repository. It is a Claude Code
workflow, which setup installs in the project and turns on.

## Dashboard panels and mobile use

Open the HTTP address setup prints. If you lost it, the read-only job-file
command prints the path to the service configuration; read that file for the
port. The status command checks whether the job is running:

```bash
bash "$PLUGIN/scripts/dashboard.sh" --job-file
bash "$PLUGIN/scripts/dashboard.sh" --status
```

The restart command restarts the collector service, as the page's "Restart collector" button does. The import
command takes the limit history, panel layout and cleared builds from another collector's dashboard folder, when a
project moves to this one:

```bash
bash "$PLUGIN/scripts/dashboard.sh" --restart
bash "$PLUGIN/scripts/dashboard.sh" --import <folder>
```

| Panel | Shows |
|---|---|
| Alerts | Current project and machine warnings, with source freshness; the last 24 hours' cleared alerts, folded. Main compacting before it restarted, and a checkpoint whose carry-over the stop hook could not heal, each raise one until main's next restart. |
| Builds in progress | Active builds and their progress. |
| Needs the owner | Open decisions and questions; the open GitHub issues labelled `P1` and those labelled `proposed-decision`, each as the five lowest numbers linked to the issue and a show-all for the rest (up to 1000 issues read). The summary strip counts the open P1 issues. |
| Main | Branch state against its remote and recent commits; the last merged unit and when. |
| Units | Planning, Building, In review, Fixing and Waiting on main, with seat activity and cost. A Builder's card says how its seats were launched (model and effort, the Builder and the current round's reviewer) and shows a Builder's open question to main as a stop note. A unit with an open task whose worktree is gone is listed under Parked. Units merged since the last push are listed apart, and finished builds have no cap. |
| Merge line | Open GitHub pull requests and their checks. |
| Who holds what | GitHub issues grouped by milestone and the unit holding each; open issues by priority; issues opened and closed in 24 hours, and a 7-day sparkline. |
| Next push | Local main commits ahead of origin/main and related checks. |
| 7-day limit | Account usage windows where available, history and list-price spend; API billing uses a spend view. |
| Main's to-do list | The project's `todo/main-todo.md`. |
| Host | Machine load and swap readings. |
| Tokens per role, 7 days | Input/output totals across roles and models, with a row for the main and relay sessions. |
| Tokens per unit, 7 days | Each unit's cost, Claude and Codex apart, with its stages. |
| Review loop, 7 days | Merged units' review rounds, most first, and the issues tagged as review escapes. |
| Tests running now | Test runs going now on this machine in the project's checkout and worktrees (from `ps`): who started each, elapsed time and usual time, `Stalled` past its cap; and the last 24 hours' finished runs with passed/failed totals (from Claude session logs); the share of the Builders' working clock spent in tests today. A run needs a `run-shell-tests.sh`, `npm test`, `.test.sh` or `node --test` command; cap is 3 times the usual time (from 3 runs), else 120 s a named test file. |
| Recent guard blocks | Recent blocking hook events and counts. |
| Chief of Staff's inbox | Relay messages for the project. |
| Main's background agents | Main's running helper agents. |
| Main and Chief of Staff seats | Whether the seat is working now, its last 12 hours of tokens, its seven-day totals, the cost of rebuilding its context after a restart (main), the helper runs it started today (Chief of Staff), and the account it runs under. |

Panels can be reordered, resized, folded and hidden. Needs a look filters for
warnings and pending work. Layouts are kept per project in browser storage
and saved on the dashboard host, so another browser can pick them up. Besides
these layout writes, only a page on the dashboard's own machine can change
anything: answer a decision, clear an unsent answer, or restart the collector.
It does not merge branches.

At phone width, panels use one column with bottom navigation (Home, Units, Builds, Tests, Alerts, You, More) and stage chips.
To reach the page from another device, choose network access in setup, or
apply the corresponding settings. Store the password first (above); setup stops
with exit 5 and says so until one is stored:

```bash
python3 "$PLUGIN/scripts/dashboard_serve.py" set-password <user>
bash "$PLUGIN/scripts/setup.sh" --dashboard --bind 0.0.0.0 --hosts <dashboard-name>
```

Replace the name with the one the other device uses for this machine. This
changes the machine's shared dashboard service. Use the printed port. Unknown
DNS names are refused, but IP access and the machine's own names are allowed.

Each project also has its own address, `/p/<name>/`, which sends the browser to the page with that project open
(`index.html?project=<name>`). Only a project name the collector lists is sent on; any other path under `/p/` is
refused. The address sits behind the same login as the page.

The collector builds a project's two slowest groups (the subagent ledger and the hook fire log) beside the rest, and
`partSeconds` in `data.js` names how long each group took.

To see how much of a restarted main's first context its checkpoint takes, run the
restarts report. It reads the `<session id>.resumed-from` records beside the stop
hook's log and gives restarts per day, the median checkpoint size, the median
context of the new session's first request and the share between them (an
estimate: 4 bytes to a token):

```bash
python3 "$PLUGIN/scripts/dashboard_limit.py" restarts ~/.claude/checkpoints/clear-hook.log [--since <iso>] [--until <iso>]
```

## Switching from another collector

The relay's decision watcher reads this plugin's decision ledger, not the other
collector's file. If you retire the other collector first, the relay hears no new
decision. Do the steps in this order, with the other collector still running until
step 7:

1. Take the limit history, layouts and cleared builds from the other collector's
   folder: `bash "$PLUGIN/scripts/dashboard.sh" --import <old folder>`.
2. Register the home checkout, then each other project:
   `bash "$PLUGIN/scripts/dashboard.sh" --register <main checkout>`. A registry
   that exists and does not list the home checkout turns the home project off, so
   register it by name.
3. Check that the built `data.js` lists the home project under `.projects`.
4. Install the job: `bash "$PLUGIN/scripts/dashboard.sh" --install`.
5. In the relay's pane, start `cos-watch-decisions.sh` and `cos-watch-alerts.sh`
   from the plugin, beside the old watchers.
6. Gate: add one test decision that waits on you
   (`bash "$PLUGIN/scripts/decision.sh" add <id> <question> <default> <source>`)
   and see `cos-watch-decisions.sh` wake. Raise or wait for one alert in the new
   `data.js` and see `cos-watch-alerts.sh` wake. Then answer the test decision.
7. Only then stop the old collector's job, remove its data file and stop its
   old watchers.

## Units mod

The units mod shows your live units, merges and test runs in three places: a
band above the prompt, a side pane named `Units` and the pinned status line. It
also toasts a verdict that changed and a unit that merged. `/units` prints the
same table in the chat. The mod only reads. It writes no file.

It runs in a project that setup has configured (the main checkout has
`.claude/commandeck.json`) and nowhere else, so other projects on the profile
are not changed. It loads with the rest of the plugin: there is nothing to add
to the settings.

### Toggles

Each place has its own option in `/config`: `unitsBand`, `unitsPane` and
`unitsStatus` (the status line and the toasts for a verdict or a merge). Each is
`auto`, `on` or `off`. `auto` is on in main and in the Chief of Staff pane, and
off in Builder, worker and reviewer panes. `/units band|pane|status on|off`
changes one for the current session. The doctor shows the three values.

### What it reads

- The dashboard snapshot, `~/.commandeck/dashboard/data.js`: this project's
  units, the verdicts, the cost and the units merged since the last push. The
  dashboard job writes it every 60 seconds. If it is missing, run
  `bash "$PLUGIN/scripts/dashboard.sh" --install`.
- A merge: `merge-unit-local.state` in main's git folder (written while a merge
  holds main), the `merge-unit-local.queue/` folder beside it (a merge that
  waits for the lock) and `$PP_SCRATCH/merge-<unit>.log`. A log holds one block
  per attempt, each starting with an `ATTEMPT unit=<unit>` line. The mod reads
  only the newest block. A log from before this line existed shows nothing.
- A test run: `commandeck-test-live/<pid>.tsv` in main's git folder and in each
  unit's worktree folder. `scripts/run-shell-tests.sh` keeps this table while it
  runs. A table counts while its process is alive. A run that the plugin hands
  to another machine shows no progress here.
- A planning unit: the seat records `$PP_SCRATCH/seat-<unit>-<role>.txt` (a
  record with a `verdict=` line is done, a launched seat with no verdict is
  running) and the plan's `Closes:` line, which lists the issues.

### How a merge reads

For each unit, the first rule that matches decides:

1. The merge state names the unit and its process is alive: running, at the
   state's stage.
2. A queue entry for the unit holds a live process: running, with no stage yet.
3. The merge state names the unit, its process is dead and the file is less than
   an hour old: stopped.
4. No state, a log less than an hour old, and its newest attempt has a `DONE`
   line: finished (a toast, no row).
5. The same, with a `FAILED` line: refused, with its step and reason.
6. The same, with neither line: stopped.
7. Otherwise nothing.

The band lists running merges only. A stopped or refused merge shows in the side
pane and in `/units`.

A merge that runs in the foreground of a pane other than main writes no log, so
its row shows no file counts until it ends. A plan seat whose pane died before
collect reads as running until main collects it.

The mod shows these messages instead of failing: `units: no dashboard snapshot`,
`units: snapshot unreadable`, `units: snapshot too big`, `units: this project
is not in the dashboard snapshot`, `dashboard data is <n> min old` and `merge
<unit>: log too big (<n> MB)`. A red mark means the Builder pane sits at its
prompt.

### Tests

Run `claude plugin test .` and `claude plugin validate .` from the plugin folder.

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
setup prints the address. It has no login. On the loopback bind it answers
403 to any other host name; `--bind` and `--hosts` at setup open it to your
own network, and it still has no login there. Network mode also accepts
the machine's own names and IP addresses; the hosts list is not an
authentication mechanism.

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
| Alerts | Current project and machine warnings, with source freshness; the last 24 hours' cleared alerts, folded. |
| Builds in progress | Active builds and their progress. |
| Needs the owner | Open decisions, questions and high-priority findings. |
| Main | Branch state against its remote and recent commits. |
| Units | Planning, Building, In review, Fixing and Waiting on main, with seat activity and cost. |
| Merge line | Open GitHub pull requests and their checks. |
| Who holds what | GitHub issues grouped by milestone and the unit holding each; issues opened and closed in 24 hours, and a 7-day sparkline. |
| Next push | Local main commits ahead of origin/main and related checks. |
| 7-day limit | Account usage windows where available, history and list-price spend; API billing uses a spend view. |
| Main's to-do list | The project's `todo/main-todo.md`. |
| Host | Machine load and swap readings. |
| Tokens per role, 7 days | Input/output totals across roles and models. |
| Tokens per unit, 7 days | Each unit's cost, Claude and Codex apart, with its stages. |
| Review loop, 7 days | Merged units' review rounds, most first, and the issues tagged as review escapes. |
| Recent guard blocks | Recent blocking hook events and counts. |
| Chief of Staff's inbox | Relay messages for the project. |
| Main's background agents | Main's running helper agents. |

Panels can be reordered, resized, folded and hidden. Needs a look filters for
warnings and pending work. Layouts are kept per project in browser storage
and saved on the dashboard host, so another browser can pick them up. Besides
these layout writes, only a page on the dashboard's own machine can change
anything: answer a decision, clear an unsent answer, or restart the collector.
It does not merge branches.

At phone width, panels use one column with bottom navigation and stage chips.
To reach the page from another device, choose network access in setup, or
apply the corresponding settings after reviewing that the server has no login
and uses plain HTTP:

```bash
bash "$PLUGIN/scripts/setup.sh" --dashboard --bind 0.0.0.0 --hosts <dashboard-name>
```

Replace the name with the one the other device uses for this machine. This
changes the machine's shared dashboard service. Use the printed port. Unknown
DNS names are refused, but IP access and the machine's own names are allowed.

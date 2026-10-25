# What you need

| Need | For |
|---|---|
| [Orca](https://github.com/stablyai/orca), and its command under the name `orca-ide` on `PATH` | worktrees and panes |
| Claude Code | every session |
| git | worktrees, the merge |
| GitHub CLI (`gh`), signed in | the issues a merge files for findings left open, and the dashboard |
| `jq`, `perl`, Python 3.11 or newer, Bash 4 or newer | the scripts and the hooks |
| ripgrep (`rg`) | a Codex pass runs each reviewer's class search with it |
| GNU `sed`, `stat`, `date`, `readlink`, `grep`, `realpath`, `timeout`, `sha1sum` and `sha256sum`; `flock` | the scripts |
| Codex CLI and the `openai-codex` Claude Code plugin, both signed in | the `claude-openai` profile only: its review passes run on Codex |

The service code supports macOS with launchd and Linux with systemd user
services. On Windows, use WSL with systemd user services available; there is
no native Windows service backend. The table is
the list in `scripts/requirements.sh`, shared by setup and the doctor.
Scripts also run the common preflight on macOS. The setup skill checks all of it at once and names
what is missing in two groups. What a package manager supplies comes with the
one command for your machine (Homebrew on macOS, apt-get on Linux), and set-up runs that command when you say yes, and
nothing without it. The rest is yours to do, each with its printed step: Orca,
Homebrew itself, GitHub sign-in and the Codex CLI. For GitHub:

```bash
gh auth login
```

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

The dashboard collects registered projects whose `origin` is on GitHub.
Other git hosts have no dashboard integration. The agents, jobs and worktrees
run on one machine; model requests and GitHub calls use the network. The merge
script makes a local squash commit on `main`. Pushing it is yours to do.

Claude Code must already be installed and signed in, at version 2.1.271 or
later: the plugin's `/config` options use pickers, which came in that version.
The repository declares no minimum Codex CLI version. CI validates the plugin
with Claude Code 2.1.302; that is a test pin. The Codex
profile also needs Node.js to run the companion from the separately installed
Codex plugin. Add-ons have their own requirements. Tests additionally use
ripgrep and Node.js; see [Tests](tests.md).

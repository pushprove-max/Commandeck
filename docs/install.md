# Install

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

Add this repository as a Claude Code marketplace, then install its plugin.
Replace `<marketplace-source>` with this repository's GitHub owner/repository
or the path to a local clone. The repository URL is also recorded in
[the plugin manifest](../.claude-plugin/plugin.json).

In Claude Code, as two separate prompts:

```text
/plugin marketplace add <marketplace-source>
```

```text
/plugin install commandeck@commandeck
```

Or from a terminal:

```bash
claude plugin marketplace add <marketplace-source>
claude plugin install commandeck@commandeck
```

Open a Claude Code session in your project's primary git checkout on `main`:

```text
/commandeck:setup
```

The setup skill checks requirements, asks the questions below, shows a plan,
and applies it only after you choose Apply. The underlying `setup.sh` script
asks nothing: its flags are the answers. Do not run it without choosing them.
A rerun keeps saved answers for flags you leave out.

Setup records each managed path before changing it. Existing user files it
manages get a visible sibling backup named `<file>.commandeck-bak-<date>`.
The install manifests and original content blobs live in
`~/.commandeck/install/`. Add-on installers run their own commands; those
external changes are not all covered by the file restore mechanism.

Setup writes the project config and settings, permission rules, git's local excludes, brief templates and the test-audit
workflow. Depending on your answers it also changes global rules, an AGENTS.md block, Codex hooks
and trust, prompt cache settings and auto-mode entries. It installs a main
watcher job and, if enabled, the machine's dashboard job. It creates an Orca
run and can create the Chief of Staff worktree and pane. Its output lists what
changed, what needs you and what is optional. It never commits. Review and run
the exact commit command it prints so new worktrees inherit the shared files.

Then check the wiring:

```text
/commandeck:doctor
```

The doctor reports failures and warnings without applying fixes. A failure
may name a command or explain what to repair. Resolve those before launching
a build. Start fresh sessions after changing hooks or startup settings.

For terminal examples below, `$PLUGIN` is the installed plugin folder. Setup
prints its full path in the doctor command. Setup also maintains this stable
link, so after setup you can use:

```bash
PLUGIN="$HOME/.commandeck/plugin"
bash "$PLUGIN/scripts/doctor.sh"
```

Run project commands from the primary checkout. These scripts live in the
plugin folder, not in your project.

## Updating

First update the plugin:

```bash
claude plugin update commandeck
```

Then, in each configured project:

```text
/commandeck:update
```

Or run `scripts/update.sh` from the **new plugin folder** printed by Claude
Code. Do not start an update through the stable link while it still points
at the old version.

```bash
bash "<new-plugin-folder>/scripts/update.sh"
```

Update prints the changelog, reruns setup with saved answers, refreshes the
managed hooks, permissions and jobs, and runs the doctor. Setup's add-on
selection is not saved: an update attempts the default add-on list again.
On failure, update restores the recorded files. Jobs may still need a rerun
of setup from the old folder, and external add-on updates are not rolled back.
The failure output names that limitation.

The update skill also checks whether the relay worktree is behind `main` and
offers to rebase it. It refuses a dirty relay or a conflicting rebase. Start
new Claude and Codex sessions after updating; open sessions retain startup
state.

An unknown config schema is refused; the update skill recommends uninstalling with the old
plugin and setting up again. There is no automatic schema migration.

To return to an earlier release, install that release with Claude Code's
plugin management, then run its update script. This repository does not
supply a version-selection flag for the external CLI.


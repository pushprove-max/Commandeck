# Uninstalling

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

In every configured project, while the plugin is still installed:

```text
/commandeck:uninstall
```

The skill asks whether to keep or delete gathered data. The equivalent
terminal commands are alternatives; choose one:

```bash
bash "$PLUGIN/scripts/uninstall.sh"
```

```bash
bash "$PLUGIN/scripts/uninstall.sh" --delete-data
```

Uninstall stops that project's watcher, removes its dashboard registration
when setup added it, and restores managed project files. In merged settings
it removes the plugin's entries and preserves your later edits. A `changed
since setup` line means that file cannot be restored byte for byte. The last
project releases the machine's managed Codex hooks, dashboard job, global
entries, installed Ponytail skill and unchanged managed status line.

By default it keeps decision, seat and helper ledgers, scratch, hook logs,
rulings, relay state and finished-build records. Delete-data removes those
for this project, and the dashboard's generated data with the last project.
It can be run later to remove kept data. It leaves briefs, review rounds,
checkpoints, HTML reviews, Claude/Codex transcripts, your visible backup
copies and external add-ons. It does not promise to remove active Builder
or relay worktrees: inspect those in Orca and keep any unfinished work.

After uninstalling the wiring in every project, remove the plugin package:

```bash
claude plugin uninstall commandeck
```

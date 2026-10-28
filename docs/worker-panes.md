# What each pane starts with

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

A worker pane starts with less context than main. `scripts/worktree-setup.sh`
writes the settings into its `.claude/settings.local.json`.

| Seat | Startup settings |
|---|---|
| Main | The worktree setup script does not change main. |
| Worker or Builder | Disables business plugins, memoir, selected connectors and code/browser tools; disables auto memory; drops Stripe and three browser skills unless kept. |
| Chief of Staff | Disables code and business plugins, selected MCP servers and connectors; uses relay-only permissions. |
| Fast lane | A worker with a 1-hour prompt cache, no Stop hook that wakes main, and no pane budget. It may spawn Sonnet and Haiku helpers (the Agent tool is allowed). For small work only: commit in the lane, run `bash $PLUGIN/scripts/fast-lane.sh review`, then main runs `fast-lane.sh land`, which merges only the reviewed commit. |
| Research lane | A worker with a 1-hour prompt cache, no Stop hook that wakes main, no pane budget and `effortLevel` high. It may spawn Sonnet and Haiku helpers (the Agent tool is allowed). It builds nothing and commits nothing; each session starts with `git merge --ff-only main`. |

A setup rerun applies the lanes' helper allowance to a lane that already exists.

A brief must carry facts the worker needs because auto memory is off.
The exact tool and plugin lists live in `scripts/worktree-setup.sh`.
A keep word restores its named skills and plugins. Billing keeps Stripe;
all skips the additional skill/plugin and auto-memory cuts.
It does not undo the earlier worker tool, MCP, business-plugin or memoir settings.

```bash
bash "$PLUGIN/scripts/builder-launch.sh" --keep billing add-csv-export .claude/briefs/add-csv-export-batch.md
bash "$PLUGIN/scripts/worktree-setup.sh" "<worktree-path>" --keep billing
```

The keep list is stored in the worktree; a rerun without it retains that list.
The doctor warns about main-checkout settings that can shadow the worktree's.

Your own lists go on top. Setup asks for the skills and plugins worker and Builder panes turn off, and for keep
words: `workerSkillsOff` (skill names, written as `skillOverrides` `"off"`), `workerPluginsOff` (`plugin@marketplace`
keys, written as `enabledPlugins` `false`) and `keeps` (a word and the skills and plugins it brings back) in
`.claude/commandeck.json`. A keep word brings its set back for one unit, a plugin cut by default (the business
plugins, memoir) included; a rerun after a list shrinks takes the dropped names back out. A name you set
yourself in a worktree's `settings.local.json` keeps your value. The extra user lists default to empty; the built-in cuts still apply. Plugin
skills cannot be turned off one at a time. Only a whole plugin can be.

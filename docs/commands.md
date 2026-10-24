# Commands and skills

The plugin ships seven skills. Type these in Claude Code; setup, update,
uninstall, handoff, worktreereview and revoke require an explicit user invocation.
Doctor can also be selected by the model when diagnosing wiring.

```text
/commandeck:setup
/commandeck:doctor
/commandeck:update
/commandeck:uninstall
/commandeck:handoff
/commandeck:worktreereview <unit>
/commandeck:revoke [[undo] rule <rule> | [undo] auto-mode <line> | status-line [--keep] | option <plugin> <key> [--keep] | undo status-line | undo option <plugin> <key>]
```

| Skill | Use it for |
|---|---|
| setup | Requirements, first-time setup and changing saved answers. |
| doctor | Read-only wiring diagnosis. |
| update | Repointing managed state after a plugin update. |
| uninstall | Removing project wiring and choosing whether to delete gathered data. |
| handoff | Checkpointing and restarting the main session on demand. |
| worktreereview | A running or finished unit's HTML time, token and cost report. |
| revoke | Taking out one of setup's values in an Orca profile's settings: a permission rule, an auto-mode line, the status line or a /config option. For the status line or an option, `--keep` keeps the value you set yourself. Under Orca, each launch puts setup's settings back, so a hand edit is undone. A choice made here holds for every pane on the profile. A setup rerun leaves a chosen value out and says so. `undo` takes a value off the list; setup's value is back at the next launch. With no argument, it lists setup's values. |

Setup also installs this project workflow. Give it repository-relative
folders, a mode and optionally a worker count:

```text
/test-audit src full 4 agents
```

With no mode it uses Basic. The count is 1–16, default 4. Basic looks
for mechanical test problems; Full also looks for missing coverage. It writes
scratch reports, leaves repository files alone and runs no tests.

If you enable the bundled Ponytail skill, invoke it separately:

```text
/ponytail
```

It supplies smallest-change coding rules. It is not a seventh Commandeck
plugin skill. Optional add-ons can expose their own commands.

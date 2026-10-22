# Commands and skills

The plugin ships six skills. Type these in Claude Code; setup, update,
uninstall, handoff and worktreereview require an explicit user invocation.
Doctor can also be selected by the model when diagnosing wiring.

```text
/commandeck:setup
/commandeck:doctor
/commandeck:update
/commandeck:uninstall
/commandeck:handoff
/commandeck:worktreereview <unit>
```

| Skill | Use it for |
|---|---|
| setup | Requirements, first-time setup and changing saved answers. |
| doctor | Read-only wiring diagnosis. |
| update | Repointing managed state after a plugin update. |
| uninstall | Removing project wiring and choosing whether to delete gathered data. |
| handoff | Checkpointing and restarting the main session on demand. |
| worktreereview | A running or finished unit's HTML time, token and cost report. |

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

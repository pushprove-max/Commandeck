# Layout

| Path | Holds |
|---|---|
| `.claude-plugin/` | the plugin manifest and a one-plugin marketplace |
| `config/routing.json` | each role's agent, model family and effort |
| `scripts/` | the Builder flow and the orchestrator's tools; `paths.sh` is the one home of every path |
| `hooks/` | the hook scripts and `hooks.json`, which registers them |
| `dashboard/` | the dashboard's page; `scripts/dashboard.sh` collects its data |
| `templates/`, `skills/` | the brief, checkpoint and Codex templates and the test-audit workflow; the setup, doctor, update, uninstall, handoff and build review skills |
| `ci/` | the leak test, its word list and the release-version check |

Plugin state lives under `~/.commandeck/`, with project ledgers, Claude logs
and Codex logs in the locations below; the record of what setup changed is in
`~/.commandeck/install/`. Worktrees go under `~/orca/workspaces/<project>/`.
Environment overrides start with `COMMANDECK_`; `scripts/paths.sh` lists the
path ones.

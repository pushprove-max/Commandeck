# Troubleshooting

Start with the doctor in the primary checkout and keep its FAIL and warn
lines. Do not treat a successful setup exit as proof that optional add-ons
worked.

| Symptom | What to check |
|---|---|
| Setup lists missing tools | Install the reported tools, or accept its exact package-manager command. Compare shell PATH with `env.PATH` in global Claude settings. Setup does not edit that PATH. |
| Hooks say no Bash 4+ | Install a newer Bash; on macOS use the Homebrew package. Until then the plugin's hooks check nothing. |
| Linux/WSL jobs do not start | Make sure systemd user services are available for the logged-in user. There is no Windows-native backend. |
| Setup refuses a duplicate project name or record | It guards shared watcher/log names and normalized path collisions. Use a distinct checkout folder name or uninstall the conflicting project first. |
| Builder refuses to launch | Commit the referenced nonempty plan on main, check the batch path and review preflight, or record an explicit reason to skip the plan. |
| Codex reviewer cannot start | Check Codex sign-in, the separately installed Codex plugin's companion, account models and any fast-tier setting. The real pass also probes provider access before committing. |
| Claude-only review cannot start | Check that the configured Claude reviewer role is usable and Claude is available. If you changed the Builder to Sonnet, choose a different reviewer family yourself. |
| Merge refuses proof | Review the current tip again as directed. Missing reviewer sessions or saved prompts cannot be replaced by typing GO into a round file. |
| Merge check is red | Fix the reported failure in the Builder. The squash is undone; rerun review if the code changes. |
| Merge exits 3 | The commit already exists. Finish cleanup by hand. |
| Dashboard is missing or stale | Check its status and job file, its registered GitHub origin, GitHub sign-in, and each source's error/freshness. A slow collector adds time to the 60-second sleep. |
| Dashboard returns 403 | Open its own page at the loopback address, or use a configured network name/IP. Cross-site requests are refused. |
| Relay is silent | Check the stored relay name, project run, all four watchers and `cos-check.sh`. FYI notes wait for a waking message. |
| Worker waits on an unseen picker | Workers must send questions through Orca to main; only main and the relay have owner-facing pickers. |
| The doctor warns that `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set for main | Remove it from main's environment and `.claude/settings.local.json`: it turns the harness task-list tools and their reminders on for every model, and main tracks work in the Orca task list. |
| Main's context grows faster than expected | `bash "$PLUGIN/scripts/context-overhead.sh" <checkout>` replays one scripted main session through the plugin's hooks and prints the bytes each attaches. A Bash hook that prints on a call with nothing to act on shows there. |
| Worktree settings have no effect | Read the doctor's shadow warnings and main's settings.local.json. Start a fresh session after fixing precedence. |
| Handoff leaves the old pane open | Read `~/.claude/checkpoints/clear-hook.log` and the next prompt's HANDOFF NOT DONE line. Fix checkpoint freshness/carry-over or Orca takeover before retrying. |
| Update fails after rewriting files | Read its rollback message. Recorded files are restored, but jobs may need old setup rerun and add-ons may already have updated. |

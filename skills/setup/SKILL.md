---
name: setup
description: Set this project up for the commandeck workflow. Use when the owner runs /commandeck:setup or says "set up commandeck", "install the workflow here". Run it in the project's main checkout.
disable-model-invocation: true
allowed-tools: Bash(bash *), AskUserQuestion
---

# /commandeck:setup

Ask once, then run one script. Do not ask anything a second time and do not
edit any settings file yourself: `setup.sh` records what was there before it
changes it, and an edit made around it cannot be undone by uninstall.

1. Ask the owner these four in ONE `AskUserQuestion` call:
   - **Profile.** `claude-openai` (Codex reviews each batch; needs the Codex
     CLI signed in and the Codex plugin) or `claude` (a second Claude reviews).
   - **Permissions.** `project` (the rules go in this project's
     `.claude/settings.json`) or `machine` (in `~/.claude/settings.json`, for
     every project).
   - **Strict hooks.** Off (the hooks that stop lost work and wrong commits)
     or on (also the hooks that hold a session to searching before reading
     and to one test run per change; needs GNU coreutils on a Mac).
   - **Chief of Staff.** The name the relay answers to and one line on how it
     should sound, or none.
2. Run it with the answers:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --profile <p> --scope <s> [--strict] [--name <n> --persona <text>]`
   Add `--test-command '<cmd>'` when the project has one command that must
   pass before a merge, and `--standard-context` when the account's model
   holds 200K. Ask in one more `AskUserQuestion` call, and only these three:
   which model builds (the plugin's own, Opus advised by Fable:
   `--builder-model '' --builder-advisor ''`; or Sonnet advised by Opus, for
   less usage: `--builder-model sonnet --builder-advisor opus`; or Opus
   advised by Opus: `--builder-model opus --builder-advisor opus`; or any
   of them with no advisor at all: `--builder-advisor none`),
   whether the dashboard is opened under another name than this machine's own
   (a tailnet name: `--hosts <name>[,<name>]`; without it such a name gets a
   403), and whether the owner wants a status line set (`--status-line
   '<command>'`, the owner's own command; the plugin ships none, and uninstall
   puts the earlier one back). If it stops, it changed nothing or says what it changed: read
   the line to the owner; `bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh`
   puts a half-done setup back.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` and show every line that
   is not `ok`.
   Tell the owner what setup added for tests: `/test-audit <scope dir...>
   [basic|full] [N agents]`, a report-only audit of a test directory by Haiku
   agents, checked at the end by a Sonnet agent. It needs the Workflow tool,
   which setup switched on in the project's `.claude/settings.json`
   (`"enableWorkflows": true`). After an edit to
   `.claude/workflows/test-audit.js` it needs a new session.
4. Show the owner the add-on list setup printed, as printed. Install none:
   setup has installed the one it installs, the ponytail skill.
5. Offer the toy unit: one small brief (`${CLAUDE_PLUGIN_ROOT}/templates/_builder-brief-template.md`)
   launched with `builder-launch.sh`, to see a Builder, a review pass and a
   local merge end to end. Then ask for the first real request.

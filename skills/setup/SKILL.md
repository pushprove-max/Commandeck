---
name: setup
description: Set this project up for the commandeck workflow. Use when the owner runs /commandeck:setup or says "set up commandeck", "install the workflow here". Run it in the project's main checkout.
disable-model-invocation: true
allowed-tools: Bash(bash *), AskUserQuestion
---

# /commandeck:setup

Ask each question once, then run one script. Do not re-ask what the owner
answered, and do not edit any settings file yourself: `setup.sh` records what
was there before it changes it, and an edit made around it cannot be undone by
uninstall.

Rule: a refused or failed question call is not an answer; ask the same thing again in plain text and never assume a default.

Rule: fixed choices go through `AskUserQuestion`, in the calls below, with exactly the headers and options written here; names and commands are asked in plain text.

1. Send this call:

   Call 1 (`AskUserQuestion`)
   Ask "Profile": claude-openai | claude
   Ask "Permissions": project | machine
   Ask "Strict hooks": off | on
   Ask "Relay": none | name one

   - **Profile.** Sent as `--profile <p>`, and Permissions as `--scope <s>`.
     `claude-openai` (Codex reviews each batch; needs the Codex
     CLI signed in and the Codex plugin) or `claude` (a second Claude reviews).
   - **Permissions.** `project` (the rules go in this project's
     `.claude/settings.json`) or `machine` (in `~/.claude/settings.json`, for
     every project).
   - **Strict hooks.** Off (the hooks that stop lost work and wrong commits)
     or on (also the hooks that hold a session to searching before reading
     and to one test run per change; needs GNU coreutils on a Mac). On sends
     `--strict`, off sends `--no-strict`.
   - **Relay.** The Chief of Staff. On "name one", ask in plain text for the
     name the relay answers to and one line on how it should sound. On
     "none", pass `--name '' --persona ''`.
2. Send these two calls, then ask in plain text for what a "name one", "set
   one" or "another name" answer needs:

   Call 2 (`AskUserQuestion`)
   Ask "Model": plugin default | sonnet | opus
   Ask "Advisor": keep | none
   Ask "Context": 200K | larger

   Call 3 (`AskUserQuestion`)
   Ask "Merge check": none | name one
   Ask "Host name": this machine only | another name
   Ask "Status line": none | set one

   - **Model.** Which model builds: the plugin's own, Opus advised by Fable
     (`--builder-model '' --builder-advisor ''`); `sonnet` advised by Opus,
     for less usage (`--builder-model sonnet --builder-advisor opus`); or
     `opus` advised by Opus (`--builder-model opus --builder-advisor opus`).
   - **Advisor.** `keep` sends the Model flags as they are; `none` adds
     `--builder-advisor none` to any of them.
   - **Context.** `200K` adds `--standard-context`: the account's model
     holds 200K; `larger` adds `--no-standard-context`.
   - **Merge check.** On "name one", ask for the one command that must pass
     before a merge: `--test-command '<cmd>'`. On "none", pass
     `--test-command ''`.
   - **Host name.** On "another name", ask for the name the dashboard is
     opened under, a tailnet name: `--hosts <name>[,<name>]`; without it
     such a name gets a 403. On "this machine only", pass `--hosts ''`.
   - **Status line.** On "none", no flag: it keeps the saved setting, by design. On "set one", ask for the owner's own command:
     `--status-line '<command>'`. The plugin ships none, and uninstall puts
     the earlier one back.

   A flag left out keeps the answer of an earlier run, so every answer
   above sends its flag, except "Status line: none", which sends none
   (setup.sh never keeps a status line in its config, and refuses an empty
   one).

   Then run it with the answers:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --profile <p> --scope <s> --strict|--no-strict --name <n> --persona <text>`
   plus the flags above. If it stops, it changed nothing or says what it
   changed: read the line to the owner;
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh` puts a half-done setup
   back.
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

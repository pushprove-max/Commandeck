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

Rule: free text the owner types (the relay's name and its line, the merge check command, a host name, a status line command) is passed to `setup.sh` exactly as typed, never corrected, completed or reformatted; a suspected slip may be asked about before anything is sent, and the original is sent unless the owner changes it.

Before the first question, run one probe: `bash -c 'command -v orca-ide; true'`.
It changes nothing, and no answer from it is a failure. If a hook that is not
this plugin's refuses it (its file is not under `${CLAUDE_PLUGIN_ROOT}`), stop
there. Tell the owner which hook refused, that this plugin cannot run in this
project until that rule allows `orca-ide`, and the one command to run in their
own terminal, in this folder, with the plugin's folder written out:
`bash <plugin folder>/scripts/setup.sh --profile claude|claude-openai`. Never
edit, switch off or work round the project's own guard.

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
     and to one test run per change). On sends `--strict`, off sends
     `--no-strict`.
   - **Relay.** The Chief of Staff. On "name one", ask in plain text for the
     name the relay answers to and one line on how it should sound. On
     "none", pass `--name '' --persona ''`.
2. Send these two calls, then ask in plain text for what a "name one", "set
   one" or "another name" answer needs:

   Call 2 (`AskUserQuestion`)
   Ask "Model": plugin default | sonnet | opus
   Ask "Advisor": keep | none
   Ask "Context": 200K | larger
   Ask "Codex fast": off | on

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
   - **Codex fast.** Off sends `--no-codex-fast`: Codex's review passes run on the standard tier, whatever the Codex config on this machine says. On sends `--codex-fast`: they run on Codex's fast tier, which answers sooner and raises what each pass costs. Only the answer "on" sends `--codex-fast`.
   - **Codex model.** Not asked up front. When setup refuses because it found no model of the Codex family (it says whether Codex goes through a proxy), ask in plain text for the model id, such as `gpt-6.1-sol`, and run setup again with `--codex-model codex-reviewer=<id>`. It is saved in this project's config, so a plugin update keeps it. `--codex-model codex-reviewer=` clears it.
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

   If it stops on `requirements are missing`, it changed nothing. Show the
   owner what it printed, as printed. The "yours to do" lines are the
   owner's: plain text, never a question. If there is a "can install" group,
   show its commands exactly as printed, then send:

   Call 4 (`AskUserQuestion`)
   Ask "Install": install | stop

   - **Install.** On "install", run the same `setup.sh` command again with
     `--install-missing` added: it runs the commands it printed and no
     other, then checks again. On "stop", run nothing more. Only the answer
     "install" sends the flag; a refused call, or any other answer, never
     does.
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

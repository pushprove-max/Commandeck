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

Rule: every question goes through `AskUserQuestion`, in the calls below, with exactly the headers and options written here; the guard's decoy goes first, so a question has at most three options of its own. A typed value is a question too: its options are the likely values (the saved one, a common one), and the picker's own free-text answer takes any other. Never print a list of follow-up questions in plain text. An answer setup cannot use as given is asked again as a picker that offers only the choices setup supports.

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
   Ask "Relay": none | Chief of Staff | <saved name, if any>

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
   - **Relay.** The Chief of Staff: the name it answers to, `--name <n>`
     (typed in the free-text answer for another name). "Relay voice" in
     Call 2 is its one line on how it should sound, `--persona <text>`. On
     "none", pass `--name '' --persona ''` and ignore "Relay voice".
2. Send these four calls:

   Call 2 (`AskUserQuestion`)
   Ask "Model": plugin default | sonnet
   Ask "Context": 200K | larger
   Ask "Codex fast": off | on
   Ask "Relay voice": plain and brief | <saved line, if any>

   Call 3 (`AskUserQuestion`)
   Ask "Merge check": none | npm test | <saved command, if any>
   Ask "Host name": this machine only | <saved names, if any>
   Ask "Status line": none | <saved command, if any>

   Call 4 (`AskUserQuestion`)
   Ask "Global CLAUDE.md": skip | install | add block
   Ask "Global rules": skip | install | add block

   Call 5 (`AskUserQuestion`)
   Ask "Review rounds": no cap | 5 | 10
   Ask "Closing pass": runs | none
   Ask "Small build": 200 lines | 400 | 1
   Ask "Review flags": defaults | off | set each

   Only on "Review flags: set each", Call 5b (`AskUserQuestion`):
   Ask "Review minutes": 30 | off | 60
   Ask "Test share": 33 | off | 50
   Ask "List price": 30 | off | 100

   - **Model.** Which model builds, at effort high and with no advisor, a
     risky build included: the plugin's own, Opus (`--builder-model ''`), or
     `sonnet`, for less usage (`--builder-model sonnet`).
   - **Context.** `200K` adds `--standard-context`: the account's model
     holds 200K; `larger` adds `--no-standard-context`.
   - **Codex fast.** Off sends `--no-codex-fast`: Codex's review passes run on the standard tier, whatever the Codex config on this machine says. On sends `--codex-fast`: they run on Codex's fast tier, which answers sooner and raises what each pass costs. Only the answer "on" sends `--codex-fast`.
   - **Codex model.** Not asked up front. When setup refuses because it found no model of the Codex family (it says whether Codex goes through a proxy), ask for the model id with `AskUserQuestion` (Ask "Codex model": gpt-6.1-sol | <an id setup printed>; the free-text answer takes any other) and run setup again with `--codex-model codex-reviewer=<id>`. It is saved in this project's config, so a plugin update keeps it. `--codex-model codex-reviewer=` clears it.
   - **Merge check.** The one command that must pass before a merge, an
     option or typed: `--test-command '<cmd>'`. On "none", pass
     `--test-command ''`.
   - **Host name.** Another name the dashboard is opened under, a tailnet
     name, an option or typed: `--hosts <name>[,<name>]`; without it such a
     name gets a 403. On "this machine only", pass `--hosts ''`.
   - **Global CLAUDE.md.** The plugin's general global instructions (working
     rules, code exploration, root-cause discipline). `install` writes
     `~/.claude/CLAUDE.md` only when there is none (`--global-claude
     install`); `add block` puts them in the owner's file as a marked block,
     which a later run replaces and uninstall takes out (`--global-claude
     block`); `skip` sends `--global-claude skip`. The owner's own text is
     never changed.
   - **Global rules.** The plugin's working, review, agent and test rules,
     the same three ways: `--global-rules install|block|skip`.
   - **Review rounds.** The most Codex review passes a build may run,
     counted by the round number each pass is given. "no cap" (today's
     rule) sends `--max-rounds ''`; a number, an option or typed, sends
     `--max-rounds <n>`.
   - **Closing pass.** "runs" (today's rule: after the narrowed passes end
     GO, one more pass reads the whole branch, and its GO is the one that
     merges) sends `--closing-pass yes`. "none" sends `--closing-pass no`:
     the narrowed pass that ends GO merges, once narrowed passes have read
     every commit after the first pass. A first pass that ends GO merges
     either way.
   - **Small build.** A first pass is one reviewer under this many changed
     lines (and no `--risky` launch), else three. "200 lines" sends
     `--small-build ''`; a number, an option or typed, sends
     `--small-build <n>`. It has no off: one reviewer for every build would
     drop the three-reviewer pass a large build needs, and "1" already makes
     no build small. Say so if the owner asks for off.
   - **Review flags.** When a finished build is flagged for a written
     review: over 30 minutes of Codex review, over a third of the clock on
     tests or idle waits (and over 10 minutes of them), over $30 at list price. "defaults" sends
     `--max-review-min '' --max-test-percent '' --max-usd ''`; "off" sends
     `--review-flags off` (no build is flagged). On "set each", Call 5b's
     three answers send `--max-review-min <n|off> --max-test-percent <n|off>
     --max-usd <n|off>`: "off" turns that one check off, a default answer
     (30, 33, 30) sends `''`.
   - Numbers are passed exactly as typed. Setup refuses one it cannot use
     and changes nothing; read its line to the owner and ask that question
     again as a picker.
   - Every threshold setup asks but Small build can be turned off: "no cap"
     for Review rounds, "off" for the review flags. Off is saved as the word,
     not a large number.
   - **Status line.** On "none", no flag: it keeps the saved setting, by design. Otherwise the owner's own command, an option or typed:
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

   Call 6 (`AskUserQuestion`)
   Ask "Install": install | stop

   - **Install.** On "install", run the same `setup.sh` command again with
     `--install-missing` added: it runs the commands it printed and no
     other, then checks again. On "stop", run nothing more. Only the answer
     "install" sends the flag; a refused call, or any other answer, never
     does.

   If it printed a `codex notify: ASK:` line, Codex's notify runs the owner's
   own wrapper script, and it calls an older plugin version's hook. Setup
   changed nothing in it. Show the owner the old line and the new one as
   printed, then send:

   Call 7 (`AskUserQuestion`)
   Ask "Notify wrapper": change it | leave it

   - **Notify wrapper.** Run the same `setup.sh` command again with
     `--notify-wrapper yes` on "change it", or `--notify-wrapper no` on
     "leave it", and read its `codex notify:` line to the owner. Only
     "change it" sends yes.
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

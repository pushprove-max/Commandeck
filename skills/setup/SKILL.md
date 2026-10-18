---
name: setup
description: Set this project up for the commandeck workflow. Use when the owner runs /commandeck:setup or says "set up commandeck", "install the workflow here". Run it in the project's main checkout.
disable-model-invocation: true
allowed-tools: Bash(bash *), Bash(python3 *), AskUserQuestion
---

# /commandeck:setup

Ask each question once, show the owner every change before it is made, then
run one script. Do not edit any settings or rules file yourself: `setup.sh`
records what was there before it changes it and copies an owner's file beside
it first, and an edit made around it cannot be undone by uninstall.

Rule: a refused or failed question call is not an answer; ask the same thing again in plain text and never assume a default.

Rule: every question goes through `AskUserQuestion`, with exactly the headers and options written here, recommended option first, and each option's one-line description as written. The recommended option's label ends in " (recommended)", as written below, in every question. While setup asks, the picker guard's decoy is off (`--questions begin` below), so a question has up to four options of its own. A typed value is a question too: its options are the likely values (the saved one first when there is one), and the picker's own free-text answer takes any other. Never print a list of follow-up questions in plain text. An answer setup cannot use as given is asked again as a picker that offers only the choices setup supports.

Rule: free text the owner types (the relay's name and its line, the merge check command, a host name) is passed to `setup.sh` exactly as typed, never corrected, completed or reformatted; a suspected slip may be asked about before anything is sent, and the original is sent unless the owner changes it.

Rule: a saved answer is offered first, marked "(saved)" (and "(recommended)" too when it is that one). Only the questions that apply are asked: the step says when one is skipped.

Before the first question, run one probe: `bash -c 'command -v orca-ide; true'`.
It changes nothing, and no answer from it is a failure. If a hook that is not
this plugin's refuses it (its file is not under `${CLAUDE_PLUGIN_ROOT}`), stop
there. Tell the owner which hook refused, that this plugin cannot run in this
project until that rule allows `orca-ide`, and the one command to run in their
own terminal, in this folder, with the plugin's folder written out:
`bash <plugin folder>/scripts/setup.sh --profile claude|claude-openai`. Never
edit, switch off or work round the project's own guard.

## 0. Check first

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --questions begin`. It checks
the requirements, says what it found, and turns the picker guard's decoy off
until setup ends. It writes nothing else.

If it stops on `requirements are missing`, show what it printed, as printed.
The "yours to do" lines are the owner's: plain text, never a question. If
there is a "can install" group, show its commands exactly as printed, then ask:

   Ask "Install": Install (recommended) | I'll do it myself | Stop
   - Install: runs the commands shown above, and no other.
   - I'll do it myself: stop now; run /commandeck:setup again after.
   - Stop: set nothing up.

Only "Install" runs `setup.sh --questions begin --install-missing`; any other
answer runs `setup.sh --questions end` and stops.

Then tell the owner, in three lines: Commandeck turns this session into an
orchestrator that hands each build to a Builder pane in its own worktree, has
each build reviewed, and merges it locally only after review and tests pass.
Setup will write its config (`.claude/commandeck.json`), permission rules,
git's local exclude list, two background jobs (a watcher and, if chosen, the
dashboard), and only what the answers below choose; nothing is written until
the owner has seen the full list and said Apply. Then read back the "Found"
lines `--questions begin` printed, in plain words.

## 1. The questions

Ask them in this order, up to four questions per call.

1. Who reviews each build?
   Ask "Reviewer": Claude (recommended) | Codex
   - Claude: a second Claude session reviews; nothing else to install. `--profile claude`
   - Codex: OpenAI's Codex CLI reviews (it must be signed in). `--profile claude-openai`
   Offer Codex only if the check said "Codex reviewer: ready".
2. Where do permission rules go?
   Ask "Permissions": This project (recommended) | Every project
   - This project: in `.claude/settings.local.json`, which git never sees. `--scope project`
   - Every project: in `~/.claude/settings.json`, for every project on this machine. `--scope machine`
   A changed answer moves the rules; setup says so.
3. Only when the check printed "your project rules":
   Ask "Your rules": Merge (recommended) | Keep both
   - Merge: sessions leave out the plugin's rules your CLAUDE.md and `.claude/rules/` already state word for word. `--rules merge`
   - Keep both: sessions load the plugin's rules as they are, beside yours. `--rules skip`
   On Merge, find rules that say the same thing in other words, or disagree:
   run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/merge-rules.py ${CLAUDE_PLUGIN_ROOT}/templates/AGENT_STARTUP.md --against <each rules file> --units`
   (and the same for `templates/main-session.md`), read each printed rule
   against the owner's files, and for each one that matches only in meaning or
   conflicts, ask one question (up to four per call). Its header is "Rule <n>",
   counting from 1 (keep the printed id for the flag; never show it). Its question
   says in words what the two rules have in common, then quotes both texts whole:
   the owner's line, with its file, and the plugin's rule. For example: "Your
   CLAUDE.md and the plugin both set when to run tests. Yours: 'Run the suite
   before every commit.' The plugin's: 'Run the smallest set of tests that would
   fail.' Which should sessions follow?"
   Ask "Rule <n>": Keep mine (recommended) | Use the plugin's | Keep both
   - Keep mine: sessions leave the plugin's rule out. `--rules-drop <id>`
   - Use the plugin's / Keep both: both load (setup never edits your own text). `--rules-keep <id>`
   `--rules-drop ''` clears every earlier answer. On a rerun, an id
   already under `mergeDecisions` in `.claude/commandeck.json` is not asked
   again: only new or changed plugin rules are (a changed rule has a new id).
4. For each "your own AGENT_STARTUP.md" or "your own .claude/main-session.md"
   line the check printed, every time setup runs:
   Ask "Own startup": Merge (recommended) | Replace | Skip
   Ask "Own main": Merge (recommended) | Replace | Skip
   - Merge: yours keeps loading, and the plugin's rules it lacks are added in a marked block (shown in the preview; uninstall takes the block out); each session leaves out of the block what the project rules it loads already state. `--own-startup merge` / `--own-main-session merge`
   - Replace: sessions load the plugin's version; yours stays on disk, untouched. `replace`
   - Skip: yours loads instead of the plugin's whole version, as today. `skip`
5. Only when the check printed "your global rules", else offer Install (recommended) | Skip:
   Ask "Global rules": Merge (recommended) | Add as block | Skip
   Ask "Global CLAUDE": Merge (recommended) | Add as block | Skip
   - Merge: only the plugin's rules your `~/.claude/CLAUDE.md` lacks, in a marked block. `--global-rules merge` / `--global-claude merge`
   - Add as block: all of them, in a marked block. `block`
   - Install (no file yet): creates the file with them. `install`
   - Skip: the file is left alone. `skip`
   "Global rules" are the plugin's working, review, agent and test rules; "Global CLAUDE" its general instructions (working rules, code exploration, root-cause discipline). Your own text is never changed, and a copy of the file is made first.
6. Which model builds?
   Ask "Builder model": Opus (recommended) | Sonnet
   - Opus: best quality, with no advisor. `--builder-model ''`
   - Sonnet: uses less of your plan. `--builder-model sonnet`
   Ask "Context": 200K (recommended) | Larger
   - 200K: your account's model holds 200K tokens; panes compact sooner. `--standard-context`
   - Larger: your model holds more (a 1M window). `--no-standard-context`
   Read the check's "context window" line first. When it says 1M, or your own
   model id ends in `[1m]`, Larger goes first and is the one marked
   "(recommended)". When it found no model setting, add to the question: "Not
   sure? /model shows your model: one marked 1M, or an id that ends in [1m], is
   Larger."
   Then, one call:
   Ask "Builder effort": Medium (recommended) | Low | High | Maximum
   - The Builder's reasoning effort, the small tooling Builder's too; review seats keep their own. A bundled build keeps most of its cache saving at medium, and the saving shrinks toward max. `--builder-effort ''`, or `low`, `high`; Maximum: `max`
   Ask "Builder clear line": 180K (recommended) | 150K | 250K | Off
   - Past this much context the Builder finishes its step, writes a handoff and goes on in a fresh session of its pane: past it every turn re-reads a large cached context. `--builder-clear-line ''`, or `150000`, `250000`; Off: `--builder-clear-line off`
   Ask "Issue sizing": 40K (recommended) | 30K | 60K | Off
   - The batch brief sizes each issue; one that shares no files with the rest and needs more reading than this is proposed to the orchestrator as its own unit before the launch. `--issue-sizing ''`, or `30000`, `60000`; Off keeps today's grouping: `--issue-sizing off`
   Ask "Plan models": All (recommended) | Without Fable | Without Codex | Without both
   - The models the plan seats (the planners and judges before a build) may run on; every planning answer offers only these, and a seat whose default is left out says which model it used instead. All: `--plan-models ''`; Without Fable: `--plan-models opus,sonnet,sol,astra`; Without Codex: `--plan-models opus,sonnet,fable`; Without both: `--plan-models opus,sonnet`. On the Claude-only profile ask All | Without Fable, and Without Fable is `--plan-models opus,sonnet`.
   Ask "Plan seats on the fast tier", one multi-select question (`multiSelect: true`): None (recommended) | Planners | Codex judges | Claude judge
   - Each plan seat runs on its model's fast tier only when chosen here (Claude fast mode, Codex `service_tier=fast`): it answers sooner and costs more. None is the default, every seat on the standard tier: `--plan-fast ''`. None picked with a seat means that seat alone. Planners: `plan-author,plan-author-second`; Codex judges: `plan-judge-sol,plan-judge-astra`; Claude judge: `plan-judge-claude`; the chosen ones joined by commas, as `--plan-fast plan-author,plan-judge-claude`. Offer Codex judges only on the Claude+OpenAI profile and when the check said "Codex fast mode: available".
7. An assistant pane?
   Ask "Relay": None (recommended) | Chief of Staff | <saved name, if any>
   - None: no assistant pane. `--name '' --persona ''`
   - Chief of Staff: a pane that relays between you and the orchestrator, so you can talk to one place. `--name 'Chief of Staff'`
   A typed name is sent as `--name <n>`. With a relay:
   Ask "Relay voice": Plain and brief (recommended) | <saved line, if any>
   - its one line on how it should sound. `--persona <text>`
   When a relay already exists, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/relay-sync.sh`. If it prints `relay: <n> commits behind main`:
   Ask "Relay": Rebase it (recommended) | Leave as is
   - Rebase it: its worktree moves onto the project's local main, so its hooks and rules are current. Say how many commits behind, and that the relay pane may be running and sees the change. After Apply, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/relay-sync.sh --rebase`; it refuses and changes nothing when the worktree has uncommitted changes or the rebase conflicts: show its line.
   - Leave as is: nothing is run. Never run `--rebase` without this answer.
8. A dashboard?
   Ask "Dashboard": On, this machine only (recommended) | Off | <saved names, if any>
   - On, this machine only: a local web page of builds and costs, served by a background job, reachable from this machine only. `--dashboard --bind 127.0.0.1 --hosts ''`
   - Off: no job, no port. `--no-dashboard`
   - On plus another name: the page also answers to a name such as a tailnet's, typed as the picker's own text answer (or the saved names). This one listens on the network (`0.0.0.0`), so say so; a name not on the list still gets a 403. `--dashboard --bind 0.0.0.0 --hosts <name>[,<name>]`
9. What must pass before a merge?
   Ask "Merge check": <detected command> (recommended) | None | <saved command, if any>
   - The one command that must pass before a merge, e.g. the project's test script. `--test-command '<cmd>'`
   - None: merges wait for review only. `--test-command ''`
   Detect it first (package.json `test` script, a Makefile `test` target), and offer it first. With none detected, None is the one marked "(recommended)".
10. Strict hooks?
    Ask "Strict hooks": Off (recommended) | On
    - Off: only the safety hooks (lost work, wrong commits). `--no-strict`
    - On: also search before reading, and one test run per change. `--strict`
11. The ponytail skill?
    Ask "Ponytail": On (recommended) | Off
    - On: the ponytail skill (/ponytail), smallest-change coding rules; costs nothing until asked for. `--ponytail`
    - Off: not installed; a copy an earlier setup installed is removed. `--no-ponytail`
    Then, how long Claude keeps a conversation's prompt cache:
    Ask "Prompt cache": 5m for main and workers (recommended) | Leave as is
    - 5m for main and workers: Main, Builders, reviewers and every other worker pane keep their cache 5 minutes, subagents too. On real sessions a 5-minute cache cost about 5% less for main and 6 to 17% less for worker panes: they seldom pause long enough for a 1-hour cache to pay. Saved in `.claude/settings.json` and each worktree's `.claude/settings.local.json`. `--cache-ttl 5m`
    - Leave as is: writes nothing; what is set now stays, a 1-hour value an earlier setup wrote included (on a Claude subscription an unset cache is 1 hour). `--cache-ttl leave`
    With a relay:
    Ask "Relay prompt cache": 1h (recommended) | Leave as is
    - 1h: The relay pane keeps its cache 1 hour. It waits on you between turns, and on real sessions a 5-minute cache cost it about 85% more than 1 hour. Saved in its worktree's `.claude/settings.local.json`; its other settings stay. The doctor warns if another file overrides it. `--relay-cache-ttl 1h`
    - Leave as is: writes nothing in the relay's settings. `--relay-cache-ttl leave`
    Then, the auto-mode classifier (it checks each command in a pane run in auto mode):
    Ask "Auto mode": Add two entries (recommended) | Leave as is | Take them out
    - Add two entries: Your Claude panes run in auto mode. Two plain-English lines go into ~/.claude/settings.json, kept with Claude Code's built-in list, so its safety check knows the plugin's scripts and the relay pane. They apply in every project on this machine. `--auto-mode add`
    - Leave as is: Changes nothing in ~/.claude/settings.json; a refusal of a plugin script stays possible. `--auto-mode leave`
    - Take them out: offered only when `bash -c 'jq -e "[.entries[].autoMode // empty] | length > 0" ~/.commandeck/install/_machine.json >/dev/null 2>&1 && echo recorded; true'` prints "recorded". Removes the two lines setup added, for every project on this machine; your own entries stay. `--auto-mode remove`
    A list of yours without `"$defaults"` is left as it is (it replaces Claude Code's built-in list) and setup says how to keep that list.
12. Add-ons, one multi-select question (`multiSelect: true`):
    Ask "Add-ons": All (recommended) | serena | agent-browser | None
    - All: every add-on in `config/addons.tsv`, installed or updated to its latest on each setup run, no version pinned. codebase-memory is updated once installed (setup prints its installer's page until then), only while no session is open; the ponytail plugin only when you have it and ponytail is on. Sends no `--addons`.
    - serena: code navigation by symbol; one language-server process per project. Choosing it also turns on the two hooks that read it (`--serena`): the read-tracker nudge and the pane-budget gate.
    - agent-browser: a browser for agents; a download of a few hundred MB.
    - None: install nothing; setup prints each command to run later.
    All sends nothing; the other chosen ones are sent as `--addons <a>,<b>`, None as `--addons none`.
    Setup runs them for this main checkout and reports each as installed or failed, with the command.
13. The review loop.
    Ask "Review": Use defaults (recommended) | Tune now | Keep saved
    - Use defaults: no round cap, a closing pass, one reviewer under 200 changed lines, the default review flags. `--max-rounds '' --closing-pass yes --small-build '' --max-review-min '' --max-test-percent '' --max-usd ''`
    - Tune now: the questions below.
    - Keep saved: sends none of these flags.
    On "Tune now", one call:
    Ask "Review rounds": No cap (recommended) | 5 | 10
    - The most review passes a build may run. `--max-rounds ''` or `--max-rounds <n>`
    Ask "Closing pass": Runs (recommended) | None
    - Runs: after the narrowed passes end GO, one more pass reads the whole branch, and its GO merges. `--closing-pass yes`
    - None: the narrowed pass that ends GO merges. `--closing-pass no`
    Ask "Small build": 200 lines (recommended) | 400 | Off
    - A first pass is one reviewer under this many changed lines, else three. `--small-build ''` or `<n>`
    - Off: every first pass has three reviewers. `--small-build off`
    Ask "Review flags": Defaults (recommended) | Off | Set each
    - When a finished build is flagged for a written review: over 30 minutes of review, over a third of the time on tests or idle waits, over $30 at list price. Defaults: `--max-review-min '' --max-test-percent '' --max-usd ''`; Off: `--review-flags off`.
    On "Set each":
    Ask "Review minutes": 30 (recommended) | Off | 60
    Ask "Test share": 33 (recommended) | Off | 50
    Ask "List price": 30 (recommended) | Off | 100
    - "Off" sends `off` for that flag; a default (30, 33, 30) sends `''`; another number is sent as typed.
14. Only with the Codex reviewer:
    Ask "Codex fast": Off (recommended) | On
    - Off: the review passes run on Codex's standard tier. `--no-codex-fast`
    - On: the fast tier, which answers sooner and costs more per pass. `--codex-fast`
    Offer On only when the check said "Codex fast mode: available".
    When the check said "Codex model: not found", ask:
    Ask "Codex model": <an id the check printed> (recommended) | gpt-6.1-sol
    - the model id for the review pass; saved in this project's config. `--codex-model codex-reviewer=<id>`

Numbers and typed values are passed exactly as typed. Setup refuses one it
cannot use and changes nothing; read its line to the owner and ask that
question again as a picker.

## 2. Preview, then apply

Run the same command with every answer's flags and `--plan`:
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh <flags> --plan`. It prints every
file it would create or change (a diff for a changed one), every copy it would
make, every job and add-on, and writes nothing. Show it to the owner, then:

   Ask "Apply": Apply (recommended) | Change an answer | Cancel
   - Apply: make exactly these changes.
   - Change an answer: name the question; ask it again, then preview again.
   - Cancel: nothing is written.

On Cancel run `setup.sh --questions end` and stop. On Apply run the same
command without `--plan`. If it stops, it changed nothing or says what it
changed: read the line to the owner;
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh` puts a half-done setup back.
A real run ends the decoy's pause, whether it succeeds or fails.

If it printed a `codex notify: ASK:` line, Codex's notify runs the owner's own
wrapper script, and it calls an older plugin version's hook. Show the old line
and the new one as printed, then ask (the decoy is back: it goes first):

   Ask "Notify wrapper": Change it (recommended) | Leave it
   - Change it: run the same command with `--notify-wrapper yes`.
   - Leave it: run it with `--notify-wrapper no`; the doctor will warn.

## 3. After

Show setup's summary as printed: Done, Needs you, Optional, and how to change
an answer later. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` and show
every line that is not `ok`.

Tell the owner, in plain words: setup added `/test-audit <test folder>`, which
checks a folder of tests for ones that cannot fail or test nothing, writes a
report and changes no file; it runs as a workflow, which setup switched on in
`.claude/settings.json`.

Then ask (setup has ended, so the decoy is back and goes first):

   Ask "Demo build": Yes (recommended) | Skip
   - Yes: one small brief (`${CLAUDE_PLUGIN_ROOT}/templates/_builder-brief-template.md`) launched with `builder-launch.sh`, to see a Builder, a review pass and a local merge end to end. It takes about 25 minutes (a small build measured 24) and runs one Builder session plus one review pass.
   - Skip: go straight to the first real request.

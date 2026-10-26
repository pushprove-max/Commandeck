## What setup asks

Each question says what its choices do, offers the recommended one first
(a saved answer first on a rerun), and is asked only when it applies. While
setup asks, the picker guard's stray-keypress option is off.

| Question | Choices |
|---|---|
| Reviewer | `claude`: a separate headless Claude reviews each build (Sonnet by default). `claude-openai`: Codex reviews it (offered when the Codex CLI is ready) |
| Permissions | this project: the rules go in `.claude/settings.local.json`, which git never sees (they name this machine's plugin folder). Every project: in `~/.claude/settings.json`. A changed answer moves them |
| Your rules | asked when the project has a `CLAUDE.md` or `.claude/rules/`: merge (sessions leave out the plugin's rules yours already state word for word; for a rule that only says the same in other words, or disagrees, you choose keep mine, use the plugin's or keep both) or keep both |
| Your own startup files | asked each time for a project's own `AGENT_STARTUP.md` and `.claude/main-session.md`, which otherwise load instead of the plugin's: merge (the plugin's rules yours lack are added in a marked block), replace (sessions load the plugin's; yours stays on disk) or skip |
| Global rules, global CLAUDE.md | when `~/.claude/CLAUDE.md` exists: merge (only the rules it lacks), add as block, or skip; when it does not: install or skip. Your own text is never changed; uninstall takes out only the plugin's blocks |
| Settings | the plugin's recommended set (every `/plugin` config option at the value in `config/recommended.json`, saved to `/plugin` config: `--recommended`), choose groups (the recommended set, then each chosen group's answers on top of it), or keep saved (a rerun). A value setup skips (a Codex model on the Claude reviewer) is named in the plan. Any key can also be given alone: `--option <key>=<value>`, checked against what the key takes. A later answer beats the recommended set |
| Groups | with Choose groups: Models (this session, Builder, Fixer), Plan seats, Reviewer, Review workflow, Caches (main, worker and relay prompt cache), Builders and wakes, Units views, Auto-decide. Each key in a chosen group is asked once, with the recommended value first |
| Context | 200K or a larger window |
| Builder clear line | 180K tokens of context (the default), another count, or off: past it the Builder writes a handoff and goes on in a fresh session of its pane, and its card on the dashboard shows its context against the line |
| Issue sizing | 40K tokens (the default), another count, or off: an issue the batch brief sizes as sharing no files and needing more reading than this is proposed as its own unit when the Builder is launched; off keeps today's grouping |
| Relay | none, or a Chief of Staff pane with a name and one line on how it should sound |
| Dashboard | on for this machine only (listens on 127.0.0.1), off, or on plus another name it answers to (a tailnet's): that choice listens on the network; unknown DNS names get 403, while machine names and IP addresses are accepted |
| Merge check | the command that must pass before a merge, or none |
| Full suite | on (recommended when the whole suite takes under about 10 minutes) or off: one full run of the test command per build, beside the closing review pass; a red run is a NO-GO (`--full-suite on\|off`). On needs a merge check; setup refuses On without one, and sets a saved On off (and says so) when the check is removed |
| Strict hooks | off or on (see [Hooks](hooks.md)) |
| Main prompt cache | 1h (or 5m) for main, in `.claude/main-session.settings.json`, which only a main started with `claude --settings <that file>` reads; a value you set stays |
| Builder and worker prompt cache | 5m (or 1h) for Builders and other worker panes (`CLAUDE_CODE_PROMPT_CACHE_TTL` in each worktree's `settings.local.json`) and their subagents (`subagentPromptCacheTtl` in `.claude/settings.json`); a value you set stays |
| Chief of Staff prompt cache | 1h (or 5m) for the relay pane (its worktree's `settings.local.json`, its other settings kept); each of the three has Leave as is (writes nothing) |
| Auto mode | add two lines to the auto-mode classifier's list in `~/.claude/settings.json` (kept with `"$defaults"`; they apply in every project on this machine), leave it as is (writes nothing), or take setup's lines out; a list of yours without `"$defaults"` is never touched |
| Add-ons | All (the default), serena, agent-browser, or None; the script can select any name from `config/addons.tsv` (see [Add-ons](add-ons.md)) |
| Review loop | defaults, keep saved, or tune: the lowest severity that holds a merge (P2 by default; `--block-at P1\|P2\|P3`), the review pass cap (5 by default; `--pass-cap <n>`, never off), whether the closing reviewer is fresh (handed no earlier finding; `--fresh-closing yes\|no`), whether a closing pass reads the whole branch (it runs by default), the small-build line for a one-reviewer first pass (200; off gives every first pass three reviewers), and when a finished build is flagged for a written review (30 minutes of Codex review, a third of the clock on tests or idle waits when they also pass 10 minutes, 30 US dollars). Numbers are saved as typed; taking every default saves nothing |
| Hook trust | with the Codex reviewer only: whether every hook in the Codex home is trusted before each Codex launch (`--trust-all-hooks on\|off`) |

Then setup prints the plan: changed files with diffs, and new files with
line counts (their content is printed only when at most 30 lines), and asks Apply, Change an answer, or Cancel. Its summary ends in three
parts: what it did, what needs you (a command it could not run, files to
commit), and what is optional (a project with no `.claude/paved-road.md`
is pointed to the template that starts it), with how to change any answer later: run
the setup skill again, or the setup script with only that flag. It also creates
the project's Orca run, or prints the one command for it. A status line is changed only if you give setup a command with
`--status-line`; uninstall restores the earlier one if the setting is still
the plugin's.

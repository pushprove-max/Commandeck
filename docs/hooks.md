# Hooks

The hooks catch mistakes; they are not a security boundary against an agent
or process running as your user. Most are registered in
[`hooks/hooks.json`](../hooks/hooks.json). Builder and worker hooks are added by
`worktree-setup.sh`. A warning allows the call; a block refuses it.

The default tier applies in configured projects, subject to each hook's seat
and event checks:

| Hook | What it does and why |
|---|---|
| `git-safety.sh` | Blocks force pushes, remote branch deletion, mirror pushes and hard resets to protect work; it handles quoted command words, but does not interpret arbitrary shell evaluation. A forced `git worktree remove` is allowed only for a temporary worktree this session added on a path that did not exist, both commands one plain `git [-C <dir>] worktree add|remove` naming the absolute path: the PreToolUse call of the add writes a claim beside the path (`.commandeck-add.<name>`, the session id), and the PostToolUse call (`--record-add`, only after a call that exited 0) records ownership in the worktree's own git folder only while that claim still names the session. Any prefix git takes for a long option (`--forc` for `--force`) is read as that option. In a Builder pane (`COMMANDECK_BUILDER=1`) it also refuses a hand `git commit`, because the review pass commits what is staged; the refusal says so, and names a model co-author trailer when the message carries one. Stated limit: it reads no worktree status before the forced remove, so a forced remove of a worktree this session added deletes whatever it holds, a file marked assume-unchanged or skip-worktree included. |
| `main-edit-guard.sh` | Blocks main from writing project code, including code in its worktrees; allows instruction and documentation paths, but caps counted uncommitted files at three even under `.claude/`. |
| `merge-lock-guard.sh` | While a detached merge holds main (its pid alive in `merge-unit-local.state`, beside the merge lock in the git dir), refuses `git stash`, `checkout`, `reset`, `clean` and the other commands that move main's tree or index, and any edit of a file in main's checkout, naming the running merge. Each git call is judged on the checkout it changes (its `cd`'s, `-C`, `--git-dir`, `--work-tree`, a `bash -c` or `eval` string), so a Builder's worktree is never main. A dead pid is a stale lock and blocks nothing. |
| `duplicate-agent-guard.sh` | Blocks a second live agent in one worktree and a new job sent to a busy pane. A hand send to a seat at its prompt is blocked too, naming `seat.sh revise`; a working seat passes, as it may be parked in a wait. |
| `dependency-addition-guard.sh` | Blocks unapproved new npm packages in install commands and package edits; protects dependency and supply-chain decisions. An edit that adds something to screen is also blocked when the `package.json` on disk, or the one the edit would leave, is not valid JSON (the block names the file, not a package). Stated limit: an install inside a `case` pattern inside a double-quoted command substitution is not seen; the parser does not read `case` syntax. |
| `literal-secret-warning.sh` | Warns about quoted secret-like literals of eight or more characters in executable code; excludes tests and config/env files. |
| `agent-model-guard.sh` | Runs in every worker pane. Fills missing helper models from `roles.builder.helpers` in `config/routing.json` (Explore: Haiku, general-purpose and debugger: Sonnet); in Builder, plan-author and fix-round panes a helper of a listed type runs on its listed model whatever the call names, except that a call naming its own type's model or the search model (in any case, or as a full model id) keeps it; asks for a type when a call names none; it never refuses the call. |
| `no-poll-loops.sh` | Blocks main's sleep polling, unqualified Orca inbox checks and worker foreground waits past the cache budget (sleeps, asks, test waits and `bgrun.sh` runs and waits all count); use event waits or background jobs. In a worker, a sleep loop whose every sleep is a finite number is wrapped in `timeout` within what is left of the budget instead of refused, and exit 124 means wait again. Main's foreground `orchestration check --wait` is moved to the background instead of refused; a worker's foreground wait counts against its budget as before. |
| `worker-ask-guard.sh` | Blocks worker pickers that would never reach you; main, the relay and the standing Fast and Research lanes can ask, with a decoy first option outside setup. |
| `checklist-guard.sh` | In main's session, keeps your on-screen checklist short: refuses a ninth open item, a subject over 80 characters or holding an id (issue or PR number, message or task id, commit hash), and a mark of `completed` (a done item is deleted). A worker session is not checked, and an unreadable task folder lets the call through. |
| `write-existing-file-guard.sh` | Warns when a large edit mostly repeats existing lines, so the edit can stay small. |
| `agent-startup-context.sh` | Loads instructions for the seat; does not block. |
| `profile-settings.sh` | At a launch (session start, or `--resume`), puts setup's settings (status line, plugin options, auto-mode and permission entries) back into the active profile's settings file when Orca's copy of the home file overwrote it. A hand edit of these is undone at the next launch. A choice made with `/commandeck:revoke` holds: a value taken out, or your own status line or option kept. Runs only with `CLAUDE_CONFIG_DIR` set to a profile setup recorded; never writes the home file; does not block. |
| `resume-context.sh` | Loads a pending main checkpoint, board and run binding once; does not block. |
| `agent-awareness.sh` | Reminds main about dispatched work and unfinished state; does not block. |
| `context-line.sh` | Prompts main to checkpoint at its clear line and Builders to write a fresh-session handoff; does not block. At main's first crossing it writes the checkpoint skeleton once, and names the one `state-snapshot.sh` call with `--goal`, `--stage`, `--next` and `--open-item` that fills it. |
| `context-clear-stop.sh` | Holds main's stop for a checkpoint, checks carry-over and starts the Orca restart when eligible. |
| `ask-records-decision.sh` | Records main's picker questions and blocks repeated unresolved or recently answered questions. |
| `ask-stop-records-decision.sh` | Holds a stop when a plain-text question was not entered in the decision ledger. |
| `ruling-log.sh` | Records the owner's answers with ids (typed prompts only from main's checkout, the Chief-of-Staff worktree and the Fast and Research lanes) and flags suspiciously fast picker answers; does not block. |
| `cos-own-echo.sh` | Acknowledges the relay's own message echoes so they do not cause another turn. In main's checkout, drops Orca's nudge when no actionable message (`wakeKinds`) is unread, or while the wake window is open, or when main already woke inside that window (one wake claim, shared with `main-watch.sh`), and prints the silent-wake line on each wake it passes. |
| `cos-inbox-waiter-stop.sh` | Holds the relay's stop until all four watchers and `cos-check.sh` are alive. |
| `opus-orchestrator-autonomy.sh` | Loads main's autonomy instructions and blocks an Opus orchestrator stop asking to continue already authorized work. |

`cos-unfinished-stop.sh` ships unregistered: it would hold a stop once when the Chief of Staff's reply (main's, when no
Chief of Staff runs) leaves its own work undone. A project that wants it adds a `Stop` entry for it, through
`hooks/lib/run-hook.sh`, to its own settings.

The strict tier is off by default. Setup saves the answer as `strictHooks`
in `.claude/commandeck.json`:

| Hook | What it does and why |
|---|---|
| `test-skip-only-blocker.sh` | Blocks focused, skipped and todo tests that could hide failures. A runner alias counts as the runner: a name bound by `const`, `let` or `var` to `it`, `test`, `describe` or `context`, or imported as `it as <name>`, on one line at the start of a statement in the text the file will hold (a declaration quoted or commented mid-line binds nothing). A typed or multi-line rename, or an alias made in another module, is not seen. |
| `suite-rerun-guard.sh` | Blocks the same completed test/type-check command on an unchanged tree within 30 minutes; recognizes npm test/typecheck, tsc and Vitest. |
| `edit-content-tripwires.sh` | Blocks new CRLF, deferred-work markers and specified TypeScript/lint suppressions, with the exemptions and reason annotations in its rule table. In screen code (the project's `screenPaths`) it also blocks placeholder copy such as "coming soon" or "under construction" in code (a comment-only line is not screened; a trailing comment, and code after a closed leading comment, are) unless the plan or main's rulings name the complete line on a `Placeholder: <file> \| <complete source line> \| <why>` line. |
| `file-size-cop.sh` | Blocks a whole-file Write crossing 500 lines for TS or 400 for TSX; an Edit crossing the cap warns and asks for a follow-up. |
| `bash-guardrails.sh` | Blocks Node test runs without the 4 GB heap cap and refuses unsupported heredoc end words so commands remain inspectable. In a Builder it also refuses, in every tier, an inline Python, Perl or Node script that writes a tracked file: that edit goes through Edit. In a worker pane, a lone unbounded search is rewritten to the checkout root and capped at 200 lines, keeping the search's own exit code; main's is still refused. |
| `pane-budget-gate.sh` | On a worker's first call, looks for the configured code server (3 seconds at most, only in a session under 15 seconds old and only when no session of this machine found it down in the last 10 minutes; a stopped or zombie server counts as missing). The worktree's shared Serena (`serena-shared.sh status`) counts as up. A server still missing blocks nothing: the worker gets one note to record it as deferred for main, with a `saw:` line and the `Try:` start command, and the dashboard shows an `mcp-down-<server>` alert for 10 minutes. After the pane budget is exhausted it holds the worker for a handoff. Past main's clear line it also lets through the flagged `state-snapshot.sh --out <checkpoint>` call, its values single-quoted, and nothing chained to it. The relay and the standing Fast and Research lanes are not gated. |
| `read-tracker.sh` | Nudges shell-only source searching when configured code navigation is unused; says nothing in a session whose gate already found the server missing. |
| `batch-independent-looks.sh` | Advises batching after three turns with one read-only call each, once in a session (the advice stays in the context); also active for planning seats without strict mode, and for Builders at the second such turn. The advice lists the looks of the streak to send together, and for two or more reads inside the checkout it names the `peek.sh` command that prints them in one call. |
| `script-over-reads.sh` | Advises using a script after five same-kind files from one directory. |
| `search-log.sh` | Logs one local row per Read, Grep, shell search and code-server call: tool, a 12-hex query fingerprint (never the query), paths, result size, emptiness and the search a later call followed within the next 3 logged calls. `scripts/search-log-report.py` prints per-tool numbers; the log is `COMMANDECK_SEARCH_LOG` or `search-log.jsonl` in the scratch folder. |
| `git-ignore-warn.sh` | Warns when a written file is ignored and would not ship, except deliberate scratch paths. |
| `new-test-file-guard.sh` | Advises extending an existing test when another file already tests the imported subject. |
| `staged-index-warn.sh` | Reports indexed files whose working copies differ after a suite; this is not proof of which bytes the test read. |
| `web-fetch-blocker.sh` | Despite its name, only advises using agent-browser for browser-dependent pages; it allows the fetch. |

Only use approval overrides after the corresponding decision. For an npm
install, the approval is in the command text:

```bash
COMMANDECK_DEP_APPROVED=1 npm install <package>
```

For a direct package.json edit, the hook instead reads an exact comma-separated
package list in `COMMANDECK_DEP_APPROVED` in the worktree's settings env.
A deliberate repeat test run uses:

```bash
RERUN=1 npm test
```

Worker-specific hooks:

| Hook | What it does and why |
|---|---|
| `builder-search-guard.sh` | Blocks long consecutive searches and whole-repository searches in the Builder's main thread; sends fact gathering to Explore helpers. A search for one bare identifier gets a symbol-lookup note. |
| `read-range-guard.sh` | Blocks a Builder's Read of a whole text file over 400 lines; names a `grep -n` and a range to read instead. |
| `builder-event-log.sh` | Records tool, helper and review activity in the worktree's `.claude/builder-events.jsonl`; does not block. |
| `claude-worker-notify.sh` | Notifies main when a Claude worker stops; does not block. |
| `codex-notify.sh` | Notifies main when a Codex turn ends; does not block. |

In the Codex profile, `codex-dispatch.sh` translates Codex hook events and
patches into the registered hooks' payloads. Setup writes five event entries
in Codex's `hooks.json`. Dispatch requires a configured project and Codex
trust for the checkout or its primary checkout. Claude-only hooks marked
`# codex: skip` are omitted. `hooks/lib/run-hook.sh` finds Bash 4+; without it,
it prints a warning and none of the plugin's hooks run.

Several checks understand only npm and TypeScript. Other stacks get only the
checks whose patterns apply.

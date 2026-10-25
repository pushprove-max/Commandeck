# Hooks

The hooks catch mistakes; they are not a security boundary against an agent
or process running as your user. Most are registered in
[`hooks/hooks.json`](../hooks/hooks.json). Builder and worker hooks are added by
`worktree-setup.sh`. A warning allows the call; a block refuses it.

The default tier applies in configured projects, subject to each hook's seat
and event checks:

| Hook | What it does and why |
|---|---|
| `git-safety.sh` | Blocks force pushes, remote branch deletion, mirror pushes and hard resets to protect work; it handles quoted command words, but does not interpret arbitrary shell evaluation. |
| `main-edit-guard.sh` | Blocks main from writing project code, including code in its worktrees; allows instruction and documentation paths, but caps counted uncommitted files at three even under `.claude/`. |
| `merge-lock-guard.sh` | While a detached merge holds main (its pid alive in `merge-unit-local.state`, beside the merge lock in the git dir), refuses `git stash`, `checkout`, `reset`, `clean` and the other commands that move main's tree or index, and any edit of a file in main's checkout, naming the running merge. Each git call is judged on the checkout it changes (its `cd`'s, `-C`, `--git-dir`, `--work-tree`, a `bash -c` or `eval` string), so a Builder's worktree is never main. A dead pid is a stale lock and blocks nothing. |
| `duplicate-agent-guard.sh` | Blocks a second live agent in one worktree and a new job sent to a busy pane. |
| `dependency-addition-guard.sh` | Blocks unapproved new npm packages in install commands and package edits; protects dependency and supply-chain decisions. An edit that adds something to screen is also blocked when the `package.json` on disk, or the one the edit would leave, is not valid JSON (the block names the file, not a package). |
| `literal-secret-warning.sh` | Warns about quoted secret-like literals of eight or more characters in executable code; excludes tests and config/env files. |
| `agent-model-guard.sh` | Fills missing helper models (Explore: Haiku, general-purpose: Sonnet), forces Builder Explore calls to Haiku, and asks for a type when a call names none; it never refuses the call. |
| `no-poll-loops.sh` | Blocks main's sleep polling, unqualified Orca inbox checks and worker foreground waits past the cache budget; use event waits or background jobs. |
| `worker-ask-guard.sh` | Blocks worker pickers that would never reach you; main and the relay can ask, with a decoy first option outside setup. |
| `checklist-guard.sh` | In main's session, keeps your on-screen checklist short: refuses a ninth open item, a subject over 80 characters or holding an id (issue or PR number, message or task id, commit hash), and a mark of `completed` (a done item is deleted). A worker session is not checked, and an unreadable task folder lets the call through. |
| `write-existing-file-guard.sh` | Warns when a large edit mostly repeats existing lines, so the edit can stay small. |
| `agent-startup-context.sh` | Loads instructions for the seat; does not block. |
| `profile-settings.sh` | At a launch (session start, or `--resume`), puts setup's settings (status line, plugin options, auto-mode and permission entries) back into the active profile's settings file when Orca's copy of the home file overwrote it. A hand edit of these is undone at the next launch. A choice made with `/commandeck:revoke` holds: a value taken out, or your own status line or option kept. Runs only with `CLAUDE_CONFIG_DIR` set to a profile setup recorded; never writes the home file; does not block. |
| `resume-context.sh` | Loads a pending main checkpoint, board and run binding once; does not block. |
| `agent-awareness.sh` | Reminds main about dispatched work and unfinished state; does not block. |
| `context-line.sh` | Prompts main to checkpoint at its clear line and Builders to write a fresh-session handoff; does not block. |
| `context-clear-stop.sh` | Holds main's stop for a checkpoint, checks carry-over and starts the Orca restart when eligible. |
| `ask-records-decision.sh` | Records main's picker questions and blocks repeated unresolved or recently answered questions. |
| `ask-stop-records-decision.sh` | Holds a stop when a plain-text question was not entered in the decision ledger. |
| `ruling-log.sh` | Records the owner's answers with ids (typed prompts only from main's checkout and the Chief-of-Staff worktree) and flags suspiciously fast picker answers; does not block. |
| `cos-own-echo.sh` | Acknowledges the relay's own message echoes so they do not cause another turn. In main's checkout, drops Orca's nudge when no actionable message (`wakeKinds`) is unread, or while the wake window is open, or when main already woke inside that window (one wake claim, shared with `main-watch.sh`), and prints the silent-wake line on each wake it passes. |
| `cos-inbox-waiter-stop.sh` | Holds the relay's stop until all four watchers and `cos-check.sh` are alive. |
| `opus-orchestrator-autonomy.sh` | Loads main's autonomy instructions and blocks an Opus orchestrator stop asking to continue already authorized work. |

The strict tier is off by default. Setup saves the answer as `strictHooks`
in `.claude/commandeck.json`:

| Hook | What it does and why |
|---|---|
| `test-skip-only-blocker.sh` | Blocks focused, skipped and todo tests that could hide failures. |
| `suite-rerun-guard.sh` | Blocks the same completed test/type-check command on an unchanged tree within 30 minutes; recognizes npm test/typecheck, tsc and Vitest. |
| `edit-content-tripwires.sh` | Blocks new CRLF, deferred-work markers and specified TypeScript/lint suppressions, with the exemptions and reason annotations in its rule table. |
| `file-size-cop.sh` | Blocks a whole-file Write crossing 500 lines for TS or 400 for TSX; an Edit crossing the cap warns and asks for a follow-up. |
| `bash-guardrails.sh` | Blocks Node test runs without the 4 GB heap cap and refuses unsupported heredoc end words so commands remain inspectable. In a Builder it also refuses, in every tier, an inline Python, Perl or Node script that writes a tracked file: that edit goes through Edit. |
| `pane-budget-gate.sh` | On a worker's first call, looks for the configured code server (3 seconds at most, only in a session under 15 seconds old and only when no session of this machine found it down in the last 10 minutes; a stopped or zombie server counts as missing). A server still missing blocks nothing: the worker gets one note to record it as deferred for main, and the dashboard shows an `mcp-down-<server>` alert for 10 minutes. After the pane budget is exhausted it holds the worker for a handoff. |
| `read-tracker.sh` | Nudges shell-only source searching when configured code navigation is unused; says nothing in a session whose gate already found the server missing. |
| `batch-independent-looks.sh` | Advises batching after three turns with one read-only call each, once in a session (the advice stays in the context); also active for planning seats without strict mode, and for Builders at the second such turn. |
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

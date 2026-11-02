# Guard review for issue 513

Date: 2026-10-31. This document only proposes. A verdict needs the owner's yes, then a unit. No hook header changes here.

## Limit on all evidence

This Mac's log cannot show whether a shipped guard earns its place.

- The log covers the project `Commandeck` only. It spans 8 days: window start 2026-10-23T08:54:03Z, earliest retained row 2026-10-22T01:00:47Z.
- The Commandeck plugin is not installed on this Mac. `hooks/hooks.json` does not run here.
- Worker seats wire four hooks through `.claude/settings.local.json`: agent-model-guard.sh, builder-event-log.sh, builder-search-guard.sh, claude-worker-notify.sh. Only these four have session traffic.
- Every other row comes from self-tests that write to the real log. The evidence is non-UUID session ids, and _old-guard.sh is a fixture name (a repo grep found no file or reference for it, so this is inference).
- So `fires 0` means not wired here. A high block count means a self-test exercised the hook. Neither says anything about use.
- "Real rows" below counts rows whose session_id is a UUID. It can differ a little from the Fires column, which comes from the summary. companion-read-guard.sh and read-record.sh have UUID rows, but those are this unit's own test runs, so they are not counted as use.
- Rows with `registered: false` are not shipped in `hooks/hooks.json`. `generated-read-guard.sh`, `companion-read-guard.sh`, `read-record.sh`, `bugfix-test-lock.sh` and `ruling-cite-gate.sh` are new in this unit.
- `reasons` is empty for every row, because the reason field is new in this unit. This review has no reason counts.
- `bugfix-test-lock.sh` and `ruling-cite-gate.sh` have no file in `hooks/` in this worktree. They appear only in the closing note, from log rows, with no code read.

Usage evidence, the four seat hooks only (real rows):

- builder-search-guard.sh: 29293 allow, 113 advise, 85 block.
- builder-event-log.sh: 54668 allow.
- claude-worker-notify.sh: 997 allow.
- agent-model-guard.sh: 118 allow.

Every other verdict is judged from code alone. The default is keep, unless the code shows a reason to narrow or retire. No hook is called quiet or noisy in use.

## Never fired in this window

24 registered hooks, 0 fires, 0 blocks, 0 advises, 0 real rows. Not wired here, so no evidence either way. Hooks that do silent work say so.

| Hook | Fires | Real rows | Blocks | Verdict | Reason | Proposed retire when |
|---|---|---|---|---|---|---|
| agent-awareness.sh | 0 | 0 | 0 | keep | Code only. Silent work: prints dispatched-work state each turn for the coordinator, and only when there is something to flag. | Zero fires across 90 days of rows from a project that installs the plugin and has coordinator sessions. |
| agent-startup-context.sh | 0 | 0 | 0 | keep | Code only. Silent work: loads the startup file into context at SessionStart. Never blocks. | Zero fires across 90 days of rows from a project that installs the plugin, with sessions logged. |
| ask-records-decision.sh | 0 | 0 | 0 | keep | Code only. Silent ledger write: each AskUserQuestion becomes a decisions row. Blocks only a repeat of an open question. | The decisions ledger gets its rows from another writer, shown by 90 days of zero fires here and non-empty rows. |
| ask-stop-records-decision.sh | 0 | 0 | 0 | keep | Code only. Holds a turn whose closing question is not in the ledger. One hold per chain. | Zero blocks across 90 days of rows from a project that installs the plugin. |
| context-clear-stop.sh | 0 | 0 | 0 | keep | Code only. Restarts main in a fresh pane past the clear line (silent work) and blocks one stop without a checkpoint. | Zero fires across 90 days from a project that installs the plugin, while context-line.sh fires. |
| context-line.sh | 0 | 0 | 0 | keep | Code only. Silent work: prints one context-size line past the clear line. Main session only. | Zero fires across 90 days from a project that installs the plugin, with main sessions past 200K logged. |
| cos-inbox-waiter-stop.sh | 0 | 0 | 0 | keep | Code only. Chief-of-Staff pane only. Every other pane passes. | No Chief-of-Staff pane in 90 days of rows from a project that installs the plugin. |
| cos-own-echo.sh | 0 | 0 | 0 | keep | Code only. Drops Orca nudges that would waste a turn. Acts silently by dropping the prompt. | Zero fires across 90 days from a project that installs the plugin, with Orca nudges present. |
| file-size-cop.sh | 0 | 0 | 0 | keep | Code only. Enforces two stated caps (.ts 500, .tsx 400 lines). | Zero blocks across 90 days of rows from a project that installs the plugin. |
| git-ignore-warn.sh | 0 | 0 | 0 | keep | Code only. Warns when a written file is gitignored. A warning, no block. | Zero advises across 90 days of rows from a project that installs the plugin. |
| literal-secret-warning.sh | 0 | 0 | 0 | keep | Code only. Warns on a literal secret in executable code. | Zero fires across 90 days from a project that installs the plugin, with Edit and Write calls logged. |
| main-edit-guard.sh | 0 | 0 | 0 | keep | Code only. Blocks project-code edits in the main checkout. Linked worktrees are exempt. | Zero blocks across 90 days of rows from a project that installs the plugin. |
| merge-lock-guard.sh | 0 | 0 | 0 | keep | Code only. Active only while a detached merge holds main. | Zero blocks across 90 days of rows from a project that installs the plugin, with merges logged. |
| opus-orchestrator-autonomy.sh | 0 | 0 | 0 | keep | Code only. Prints an overlay at SessionStart (silent work) and refuses premature permission-asking stops. Opus orchestrator seat only. | Zero fires across 90 days from a project that installs the plugin, with Opus main sessions logged. |
| profile-settings.sh | 0 | 0 | 0 | keep | Code only. Silent work: restores profile settings at launch. | Zero fires across 90 days from a project that installs the plugin, with profile launches logged. |
| read-range-guard.sh | 0 | 0 | 0 | keep | Code only. Refuses a whole-file read of a text file over 400 lines, in Builders only. | Zero blocks across 90 days of rows from a project that installs the plugin, with Builder sessions logged. |
| read-tracker.sh | 0 | 0 | 0 | keep | Code only. Strict tier only, so off unless the project turns it on. | No project turns on the strict tier in 90 days of rows. |
| resume-context.sh | 0 | 0 | 0 | keep | Code only. Silent work: prints run binding, board and checkpoint into a restarted main, once. | Zero fires across 90 days from a project that installs the plugin, with main restarts logged. |
| ruling-log.sh | 0 | 0 | 0 | keep | Code only. Silent ledger write: logs every owner answer with its clock. ruling-cite-gate.sh depends on it. | ruling-cite-gate.sh is retired, or zero fires across 90 days with AskUserQuestion answers logged. |
| script-over-reads.sh | 0 | 0 | 0 | keep | Code only. Advice after the fifth file of one kind is opened from one directory. | Zero advises across 90 days of rows from a project that installs the plugin. |
| staged-index-warn.sh | 0 | 0 | 0 | keep | Code only. Reports indexed paths that differ after a test suite runs. | Zero advises across 90 days of rows from a project that installs the plugin, with suite runs logged. |
| web-fetch-blocker.sh | 0 | 0 | 0 | keep | Code only. Advises agent-browser on WebFetch and never refuses. | Zero advises across 90 days of rows from a project that installs the plugin, with WebFetch calls logged. |
| worker-ask-guard.sh | 0 | 0 | 0 | keep | Code only. Blocks AskUserQuestion in worker seats. Also stamps the picker open time (silent work) for ruling-log.sh. | Zero fires across 90 days from a project that installs the plugin, with AskUserQuestion calls logged. |
| write-existing-file-guard.sh | 0 | 0 | 0 | keep | Code only. Warns when a write mostly restates the lines it replaces. | Zero advises across 90 days of rows from a project that installs the plugin, with Edit and Write calls logged. |

## Fired with no block or advice

Hooks with fires and no block. Fires come from the summary. Only the four seat hooks have real rows.

| Hook | Fires | Real rows | Blocks | Verdict | Reason | Proposed retire when |
|---|---|---|---|---|---|---|
| agent-model-guard.sh | 1123 | 118 | 0 | keep | Seat hook, so it has usage evidence: 118 real allow rows. Silent work: rewrites a missing `model` on Agent calls through updatedInput. It never refuses, by design. | Agent calls without a `model` are zero across 90 days of real rows. |
| batch-independent-looks.sh | 112 | 0 | 0 | keep | Code only. 24 advises, all from self-tests. An advice hook, so 0 blocks is by design. | Zero advises across 90 days of real rows from a project that installs the plugin. |
| bash-guardrails.sh | 2 | 0 | 0 | narrow | Code only. 800 lines for a 4 GB heap cap plus a tripwire for scripted writes. Propose splitting by rule so each can be judged. | Zero blocks across 90 days of real rows from a project that installs the plugin. |
| builder-event-log.sh | 52345 | 54668 | 0 | keep | Seat hook with usage evidence. Silent ledger write: one JSON line per subagent or Codex event. Never blocks. builder-search-guard.sh appends to the same file. Not shipped in hooks.json. | The builder-events file has no reader (no script or report opens it) for 90 days. |
| claude-worker-notify.sh | 934 | 997 | 0 | keep | Seat hook with usage evidence. Silent work: sends an Orca message when a worker turn ends so main wakes. Not shipped in hooks.json. | Orca delivers worker-turn-end wakes itself, shown by 90 days where main wakes with zero fires here. |
| codex-dispatch.sh | 6 | 0 | 0 | keep | Code only. A dispatcher that runs the plugin's hooks for Codex. Blocks come from the hooks it calls. Not shipped in hooks.json. | Codex reads `hooks/hooks.json` directly. |
| new-test-file-guard.sh | 118 | 0 | 0 | keep | Code only. Advises when a new test file shares a subject with an existing one. | Zero advises across 90 days of real rows from a project that installs the plugin. |
| read-record.sh | 10 | 0 (10 UUID rows are this unit's test runs) | 0 | keep | Code only. Silent ledger write: records the path of every file read, only when `.claude/companions.tsv` exists. New in this unit. Its one reader is companion-read-guard.sh. | companion-read-guard.sh is retired. |
| search-log.sh | 5 | 0 | 0 | keep | Code only. Silent log: one local row per search or read, with no query text. Feeds search-log-report.py. | The report script is unused, or the code-server-versus-rg question (issue 298) is answered. |

## Blocks the most

Hooks with at least 100 blocks. Except for builder-search-guard.sh, every count here is test traffic: a self-test exercised the hook. None of it shows a refusal of an agent. Reasons are not logged, so no block can be checked.

| Hook | Fires | Real rows | Blocks | Verdict | Reason | Proposed retire when |
|---|---|---|---|---|---|---|
| builder-search-guard.sh | 33797 | 29491 (29293 allow, 113 advise, 85 block) | 1224 (85 real, the rest test traffic) | narrow | Seat hook, so the real rows are usage evidence. The code says LIMIT is "a starting value, not measured". Tune LIMIT from the real refusal rows. Not shipped in hooks.json. | Real blocks fall to zero across 90 days after the LIMIT is tuned, or Builders stop searching in a row. |
| git-safety.sh | 1101 | 0 | 722 (test traffic) | keep | Code only. Blocks dangerous git operations. Also records worktree ownership after an add (silent work, `--record-add`). | Zero blocks across 90 days of real rows from a project that installs the plugin. |
| dependency-addition-guard.sh | 1077 | 0 | 687 (test traffic) | keep | Code only. Blocks a new npm dependency without the owner's approval prefix. | Zero blocks across 90 days of real rows from a project that installs the plugin. |
| test-skip-only-blocker.sh | 642 | 0 | 367 (test traffic) | keep | Code only. Blocks `.only`, `.skip` and `xit`. Strict tier only. | Zero blocks across 90 days of real rows from a project that installs the plugin. |
| pane-budget-gate.sh | 436 | 0 | 163 (test traffic) | keep | Code only. Blocks a worker's first call without serena, and a pane past its budget without a handoff. | Zero blocks across 90 days of real rows from a project that installs the plugin. |
| edit-content-tripwires.sh | 295 | 0 | 132 (test traffic) | keep | Code only. Blocks new content that reaches for a pattern with a blessed path, unless a reason is annotated. | Zero blocks across 90 days of real rows from a project that installs the plugin. |

## Log problems found

- Self-tests write to the real fire log. Test rows (non-UUID session ids, fixture names such as _old-guard.sh) mix with session rows, so `scripts/hook-fire-log-summary.sh` reports test traffic as hook behavior. Proposed fix, for a unit: self-tests set a separate log path, or the summary drops non-UUID sessions by default.
- The review should be rerun from a project that installs the plugin. Only then do `hooks/hooks.json` hooks produce real rows, and only then can a "retire when" line be checked.

## Blockers below 100 blocks (no verdict here)

checklist-guard.sh (96 fires, 45 blocks), suite-rerun-guard.sh (253, 58, 9 advises), generated-read-guard.sh (36, 14), companion-read-guard.sh (18, 7; its UUID rows are this unit's test runs), duplicate-agent-guard.sh (17, 7), ruling-cite-gate.sh (12, 9), bugfix-test-lock.sh (5, 3), no-poll-loops.sh (2, 1). All are test traffic except where noted.

Next step: the owner rules on each verdict; a unit makes the change.

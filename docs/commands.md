# Commands and skills

The plugin ships seven skills. Type these in Claude Code; setup, update,
uninstall, handoff, worktreereview and revoke require an explicit user invocation.
Doctor can also be selected by the model when diagnosing wiring.

```text
/commandeck:setup
/commandeck:doctor
/commandeck:update
/commandeck:uninstall
/commandeck:handoff
/commandeck:worktreereview <unit>
/commandeck:revoke [[undo] rule <rule> | [undo] auto-mode <line> | status-line [--keep] | option <plugin> <key> [--keep] | undo status-line | undo option <plugin> <key>]
```

| Skill | Use it for |
|---|---|
| setup | Requirements, first-time setup and changing saved answers. |
| doctor | Read-only wiring diagnosis. |
| update | Repointing managed state after a plugin update. |
| uninstall | Removing project wiring and choosing whether to delete gathered data. |
| handoff | Checkpointing and restarting the main session on demand. |
| worktreereview | A running or finished unit's HTML time, token and cost report. |
| revoke | Taking out one of setup's values in an Orca profile's settings: a permission rule, an auto-mode line, the status line or a /config option. For the status line or an option, `--keep` keeps the value you set yourself. Under Orca, each launch puts setup's settings back, so a hand edit is undone. A choice made here holds for every pane on the profile. A setup rerun leaves a chosen value out and says so. `undo` takes a value off the list; setup's value is back at the next launch. With no argument, it lists setup's values. |

Setup also installs this project workflow. Give it repository-relative
folders, a mode and optionally a worker count:

```text
/test-audit src full 4 agents
```

With no mode it uses Basic. The count is 1–16, default 4. Basic looks
for mechanical test problems; Full also looks for missing coverage. Prune
looks only for tests to delete or merge, and each proposal names the other
test that still protects the behavior. It writes
scratch reports, leaves repository files alone and runs no tests.

Optional add-ons can expose their own commands.

## rules-audit

`bash scripts/rules-audit.sh [--repo DIR]` checks a project's rule files with fixed checks and no model. It reads
`CLAUDE.md`, `AGENT_STARTUP.md`, `.claude/main-session.md` and `.claude/rules/*.md`, and also `templates/`,
`.claude/briefs/`, `docs/` and `hooks/*.sh` (not `CHANGELOG.md`). It prints one `file:line kind detail rule: <where
the rule is written>` row per finding and exits 1 when there is one. The doctor and setup report the count as a
warning; this repository's CI runs it.

| Kind | Finding |
|---|---|
| `unknown-option` | `--option <key>=` names a key that is not in the plugin's `userConfig`. |
| `retired-name` | A name from `config/retired.tsv` (a script, hook or option the CHANGELOG retired). The row says what replaced it. |
| `dead-ref` | A backticked `templates/`, `docs/`, `scripts/`, `hooks/` or `.claude/rules/` path that is not on disk. |
| `over-200-lines` | An always-loaded rule file past 200 lines. A `docs/` file may be longer. |
| `duplicate-subject`, `stale-model`, `open-conflict` | The same rule under two headings, a pinned model id, an "OPEN conflict" marker. |
| `memory-over-limit`, `dead-index`, `orphan-memory`, `superseded-memory` | The memory folder's `MEMORY.md` is too long, links a missing file, or leaves a memory unindexed or superseded. |

## break-run

`bash scripts/break-run.sh <plan> <k>` runs the test of the plan's k-th `Break:` line after the Builder removed the
condition, and prints the row for the evidence file's `## Break runs`: `- <test file> -- <check label> -- red: <command>`.
It counts only a non-zero exit with a failure record of the named check (`FAIL <label>`, or `✖ <label> (` for node);
another check failing is no break run. Exit 0 for a break run, 1 for none, 2 for a bad line, plan or file.

## decision rulings

`bash scripts/decision.sh rulings <term>...` lists the owner's earlier picker answers whose question or answer holds a
term (any case), newest first, one `<id> <et>: <question> -> <answer>` line each. Voided picks and the picker decoy are
left out. A plan author runs it before it writes a question to the owner. No match prints nothing and exits 0.

## seat revise

`bash scripts/seat.sh revise <role> <unit> "<text>"` sends a follow-up to a seat that reported done: it settles the old
task and gives the same pane a new one, so the next finish wakes main. It refuses a Builder (use `answer-worker.sh`), a
seat with no record, and a pane that is gone or busy. The finish comes as main-watch's wake, not from `seat.sh wait`,
which still counts the first prompt's marker. `seat.sh status` shows the pane's live state as `agent=<state>`.

## peek

`bash scripts/peek.sh <file>:<a-b> '<file>#<Heading>' -g <pattern> <file>` prints several reads in one call, each under
an `== <item> ==` header (400 lines per item, 60 KB in all). `--unit <unit> [--plan <file>] [--closing]` prints a
reviewer's inputs: the diff stat, the brief, the plan without its change log and the paved road. It exits 2 on the
checkout root or its parent.

## /autodecide

`/autodecide on|off|status` lets the relay pane decide for the owner while the owner is away. It is on until `off`,
across restarts. While it is on, a band above the prompt and a status-line entry say so with a count of decisions
made, the question picker is blocked in that pane, and the system prompt carries the rules. Each decision goes through
`bash scripts/relay-order.sh --auto <id> <words> <why> <trade-off> <would-change> <reversible>`, which writes the
entry to the decision log (`.claude/metrics/autodecide-<date>.md` in the main checkout), records the answer in the
decisions ledger as `<words> (auto-decided)` and tells main. The seats that read the mode are the `autoDecideSeats`
setting; extra never-decide items go in `autoDecideNever` in `.claude/commandeck.json`. The hard limits and the
never-decide list ship fixed and are instructions to the model, not code.

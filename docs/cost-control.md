# Cost control

- Startup size. The plugin budgets hook output at 10,240 bytes to avoid
  Claude Code truncating startup context. `scripts/startup-size.sh` measures
  each seat and exits 1 over the limit; it supports `--role` and `--per-prompt`.
  Task-only rules sit in `templates/rules-details.md` behind one-line
  `Details, <path>, <Section>.` stubs, so the always-on files carry less.
- The clear line. Past 200K tokens of context (140K with
  `--standard-context`) the orchestrator gets a line on every prompt telling
  it to checkpoint. See [Checkpoints](checkpoints.md).
- The pane budget (strict tier). A worker pane past 450,000 tokens of context
  (the fallback in `config/pane-budget.json`; measured budget data can replace it)
  may not edit or run commands until it has
  written a handoff file with its decisions, open findings, current commit
  and test evidence.
- The cache check. `scripts/builder-cache-check.sh`
  reads a Builder's transcripts and fails unless its main thread and its
  subagents wrote only the prompt cache of the Builder and worker answer of the
  Builder's own project (5m or 1h; unanswered reads as 5m); with Leave as is it
  proves nothing and says so.
- The price of each build. The build review prices every request at list
  price from one table in `scripts/dashboard_limit.py` and flags a build over
  30 US dollars. These are list-price equivalents and a subscription plan bills
  differently. A model with no list price on file is shown as unpriced,
  never as zero.
  `scripts/unit-cost.sh` prints a build as turns, tool calls
  and tokens per session.
- Helper usage. `scripts/subagent-usage.sh` records one row per finished
  subagent run (type, model, tokens) in
  `.claude/metrics/subagent-usage.jsonl`. `scripts/seat-tokens.sh` totals
  tokens per unit and per role.
- The 7-day limit. The dashboard reads your account's usage and shows the
  7-day limit for Claude and Codex; the limit watcher above tells you at
  90%.

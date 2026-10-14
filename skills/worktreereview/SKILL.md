---
name: worktreereview
description: Review one finished or running worktree build (a Builder or any agent that worked in an Orca worktree) and produce an HTML report of where the time and tokens went, stage by stage, with lessons. Use when the owner says "/worktreereview <unit>", "analyze the <unit> build", "break down that build", or asks what a Builder run cost.
---

# Worktree review

Turns one worktree's logs into a report the owner can read: a clock chart, a stage table with list
prices, a drilldown per stage, tokens and cost by model, the Codex passes, and what the
reviewer makes of it. The two scripts do every number; you write only the words.

## When it runs

After EVERY worktree merge, against the unit that was merged.

That run is automatic and uses no model: main's merge step
runs one command,
```
python3 ${CLAUDE_PLUGIN_ROOT}/skills/worktreereview/scripts/review.py <worktree path> --no-open
```
which collects, renders a page whose findings are computed, files it under
`~/.commandeck/reviews/<date>/<project>/<unit>-review.html`, prints that path as its `page:` line, opens
nothing, and never fails the merge. The merge's own page is never opened as a tab: only the page
with the reviewer's analysis is, for a flagged build. A reviewer writes lessons (the steps below) only when:
- the run trips a threshold, in which case review.py sends the pane in its `--open-in` worktree one message
  "worktree review flagged <unit>". Defaults: more than 30 minutes of Codex review in
  total, more than a third of the clock on tests or idle waits, more than $30 at list price
  (`--max-review-min`, `--max-test-share`, `--max-usd`; the owner's answers at setup, saved as `reviewLoop`
  in the project config, replace these defaults); or
- the owner asks for a review, for a merged build or one still running.

It reads logs only, so it works after main has removed the worktree:
- the Claude session logs filed under the worktree's path (`~/.claude/projects/<path with - for />`),
- the helper logs beside them,
- every Codex session record whose working folder is the worktree (`~/.codex/sessions`).

## Steps

1. **Find the worktree path.** It is `~/orca/workspaces/<project>/<unit>`. If unsure, list
   `~/.claude/projects/` for the unit name. The folder need not exist any more.

2. **Collect.**
   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/worktreereview/scripts/collect.py <worktree path>
   ```
   It prints the stages, totals, clock split, Codex passes and guard refusals, and writes
   `result.json` and `notes.txt` to `/tmp/commandeck/worktreereview/<project>/<unit>/`. Stages are automatic:
   Build, then each Codex pass and the fixing between passes, then Wrap-up.

3. **Split the Build stage when it covers several jobs.** Read `notes.txt` (the agent's own
   progress notes with UTC times) and find where it moved from one issue to the next and where
   building turned into its own checks. Run collect again with one `--split` per boundary:
   ```
   --split "21:22:54=Build the two slow hooks" --split "22:08:11=Own checks before review"
   ```
   A split within a minute of the start renames the first stage. Say in the report that the
   boundaries are yours.

4. **Read what the numbers cannot tell you.** If the worktree still exists, read its evidence
   file (`.claude/briefs/<unit>-evidence.md`), above all "Not done / not checked". Read the
   Codex findings in `result.json` (`passes[].message`). Check whether main has merged it
   (`git log` on main, read-only) and what main said in the inbox.

5. **Write `notes.json`** next to `result.json`. Keys: `title`, `summary`, `stage_notes`
   (by stage code), `pass_findings` (by pass number, one plain sentence each), `lessons`
   (title and points), `not_measured`, `method`.

6. **Render and check.**
   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/worktreereview/scripts/render.py <result.json> <notes.json> <out.html>
   ```
   Every figure you quote in a lesson must match the page's tables. Recompute, do not recall.

7. **File it** where your role files reports for the owner and add the index line.

8. **Open it in Orca**, in the worktree the owner reads reports in, as a rendered page:
   ```
   orca-ide tab create --url "file://<absolute path to the html>" \
     --worktree "path:<that worktree>"
   ```
   Confirm with `orca-ide tab list --worktree "path:..." --json` that a tab carries the
   report's title. (`orca-ide file open` only takes files inside the worktree and shows the
   source, not the page.) Then give the owner the clock split, the cost and the lessons in a few lines.

## Time waiting on the owner is cut

Time a Builder sat waiting on the owner is not build time (the owner, 2026-10-14). collect.py cuts it
from every clock figure, share and flag, and leaves cost as it is: each `--exclude START=END` window
(ISO UTC, repeatable; review.py passes it through), and each idle gap over two minutes with nothing of
the build running that either follows the Builder's `<UNIT>-DONE` line until new work arrives, or sits
inside an open decision in the main checkout's `.claude/metrics/decisions.jsonl` that names the unit in
its `source` or `answer` (the last row per decision and ask wins). A gap with any session's background
job or a Codex run in it is kept, and a found window cuts only idle seconds. Overlapping windows cut
each second once. Once the worktree is removed nothing proves which checkout it came from: pass `--main <main
checkout>` (review.py passes it through), or no decision and no round archive is read. Still counted, and the page says so: a helper's request and tool subtotals, and
command seconds inside a cut Codex pass. The page and `result.json` (`cut`, `cut_s`) list every window with its start, end,
length and reason.

## The two timing sections

Every page carries them, computed, with no words needed from you:
- **Time off Claude's servers**: tools, hooks, Codex and waiting. What it was, commands grouped
  by the script they ran, hook time before and after each tool call, each logged hook, each
  idle wait, the inside of each Codex pass, and every tool call in a sortable table.
- **Time on Claude's servers, request by request**: the wait before the model began, thinking
  and writing; by what the request did, by stage, by context size and by reply size; the
  slowest requests; every request in a sortable table; and "Where it could shrink", a computed
  list (single looks sent one at a time, the fixed cost of a round trip, long thinking, long
  replies, advisor consults, cache writes, repeated commands, time-limit kills, refusals).

Each "could shrink" figure is a ceiling the code worked out, not a ruling. Use them as leads:
sort the tables, check the rows, and only then write a lesson.

## What to look for in the lessons

- The largest slice of the clock, and whether one test or command explains it
  (`background_jobs` and the idle gaps name them).
- Codex passes: how many, findings per pass, and whether several findings were one flaw
  fixed piecemeal. A pass with several threads started reviewers of its own.
- Whether work was split or batched, and what the split cost or saved.
- Calls times context: the agent's cost follows the number of model calls and the context
  each one re-reads. Note compactions and the size they fired at.
- Any tokens paid at full price: advisor calls send the context uncached.
- The dearest stage and why: open its drilldown (`stages[].detail` holds its clock split,
  longest commands with their results, files edited, guard refusals and the agent's notes).
- Faults in the tooling the run exposed, and what the agent left for main.

## Rules for the words

- Plain English, the point first. Explain a term or use a normal word.
- Tag anything you did not check as unverified or likely. Never guess a cause the logs do not show.
- Always include what the report does not measure: main's own tokens, what the plan really
  bills, hook time per tool call, quality after merge.
- Dollars are list-price equivalents, priced call by call with the repo's one price table
  (`scripts/dashboard_limit.py`, the dashboard's own). Say "list price" every time.
  A model with no price there (a Codex name with no known tier) is unpriced: never guess a rate,
  and name what the total leaves out. A new Codex version of a known tier takes the tier's
  price; say that part is priced by tier, not by exact version.
- Name each model by its name (Opus 5.5, Fable 5.1, Haiku 5.5), never only by its role.
- Helper output tokens are under-recorded in the logs; say so if you quote them.
- A lesson that proposes a change is your view. Say so, and do not present it as a ruling.

## Known limits

- The clock's "tests" slice is found by matching each command's description against
  `--test-regex`. Check a few of the longest commands before trusting a surprising number.
- A worktree reused for a second agent (a fix agent after the first) shows as two sessions;
  the time between them is "No agent session open". Use `--session <id prefix>` for one alone.
- A worktree's own `builder-events.jsonl` over-counts refusals; the report uses the session
  log instead.
- Only a hook that prints something leaves a log row, so the per-hook table is a floor. The
  hook time before and after each tool call is read from row times and is whole.
- A request starts at the last log row before its first block. The client's own API counter
  runs higher: it also counts helper agents, compaction and small background calls.
- The permission check before a tool runs sits inside "the tool itself"; it is not split out.

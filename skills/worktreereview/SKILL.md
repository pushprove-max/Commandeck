---
name: worktreereview
description: Review one finished or running worktree build (a Builder or any agent that worked in an Orca worktree) and produce an HTML report of where the time and tokens went, stage by stage, with lessons. Use when the owner says "/worktreereview <unit>", "analyze the <unit> build", "break down that build", or asks what a Builder run cost.
disable-model-invocation: true
---

# Worktree review

Turns one worktree's logs into a report the owner can read: a clock chart, a stage table with list
prices, a drilldown per stage, tokens and cost by model, the Codex passes, and what the
reviewer makes of it. The two scripts do every number; you write only the words.

## When it runs

Only when the owner asks: `/worktreereview <unit>`, for a merged build or one still running. The merge
step does not run it, and nothing else starts it (the owner, 2026-10-14).

The page of computed numbers alone, with no words from you, is one command that uses no model:
```
python3 ${CLAUDE_PLUGIN_ROOT}/skills/worktreereview/scripts/review.py <worktree path> --no-open
```
It collects, renders, files the page under
`~/.commandeck/reviews/<date>/<project>/<unit>-review.html` and prints that path as its `page:` line.
The page flags a build past a threshold. Defaults: more than 30 minutes of Codex review in total;
more than a third of the clock on tests or idle waits when those also come to more than 10 minutes, the
flag naming the largest single command; more than 30 US dollars at list price (`--max-review-min`,
`--max-test-share`, `--max-usd`; the owner's answers at setup, saved as `reviewLoop` in the project
config, replace these defaults). A wait on a review pass run outside the Builder's session (the owner
ran it) or on a review tool that was down has its own slice of the clock and counts toward no flag.

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
   (title and points), `not_measured`, `method`, and `shrink_review`: one entry for each
   "Where it could shrink" item, by its bold title, marked covered by an open issue
   (`{"item": "Long thinking", "issue": "#12"}`, citing it) or uncovered with a one-line
   proposed fix (`{"item": "Long thinking", "fix": "..."}`). The page lists the marks and
   names any item left unmarked.

6. **Render and check.**
   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/worktreereview/scripts/render.py <result.json> <notes.json> <out.html>
   ```
   Every figure you quote in a lesson must match the page's tables. Recompute, do not recall.
   The page computes the "Where it could shrink" items, so the first render may list some under
   "Not reviewed yet": add a `shrink_review` entry for each and render again.

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
(ISO UTC, repeatable; review.py passes it through), and the part of each idle gap over two minutes with
nothing of the build running that sits inside an open decision in the main checkout's
`.claude/metrics/decisions.jsonl` that names the unit in its `source` or `answer` (the last row per
decision and ask wins). A gap waiting on main or on nothing with no decision recorded is cut whole, and its
reason names the cause. Idle after the Builder's `<UNIT>-DONE` line is not cut by itself: with no owner
decision open it stays on the clock, as does time waiting on a merge. A gap with any session's background
job or a Codex run in it is kept, and a found window cuts only idle seconds. Overlapping windows cut
each second once. Once the worktree is removed nothing proves which checkout it came from: pass `--main <main
checkout>` (review.py passes it through), or no decision and no round archive is read. Still counted, and the page says so: a helper's request and tool subtotals, and
command seconds inside a cut Codex pass. The page and `result.json` (`cut`, `cut_s`) list every window with its start, end,
length and reason.

A hold main recorded with `unit-hold.sh <unit> hold|release '<reason>'` is cut the same way, reason `hold`,
except seconds a Codex run or background job covers. A stretch with no session open, no Codex run and no hold, as
long as an owner wait or longer, is listed in an "Unexplained idle" box (`result.json`: `unexplained`,
`unexplained_s`) and is not counted in any stage.

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
- Every time: is there a library, a shared helper or a cached step that would significantly
  speed up builds like this one? Answer it in a lesson, yes with what, or no.

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
- Refer to a lesson as `<unit> L<n>`: the page numbers its lessons L1, L2, ... in the order of `notes.json`.

## A lesson becomes an issue only with the owner's approval

1. Each lesson that proposes a change, and each "Where it could shrink" item the page marks
   uncovered, becomes a draft issue, never an issue: the repo, a title, a body of 2 to 4 lines, the
   labels, and the source lessons (`<unit> L<n>`) or item.
2. Put the drafts to the owner one at a time, each with its details, and wait for an answer to each.
3. File only the drafts the owner approves, as approved. A draft the owner declines or does not answer
   is not filed.

No step of this skill and no script files an issue from a lesson without that approval.

## Sweep over past lessons (on demand)

When the owner asks what became of past lessons, read the lessons of the filed review pages and, for
each lesson, say which of these it is:
- **done**: an issue closed or a commit made the change; name it.
- **filed**: an open issue holds it; name it.
- **nothing yet**.

Group the lessons that say the same thing on several pages as one, with each source lesson. For the
"nothing yet" ones, make draft issues as above, ordered by what the lessons say they cost (the
largest first), and put them to the owner one at a time.

## Writing the lessons page in a separate writer session

Use this when the session asked for the review is busy with other work and its context is large (an
orchestrator, for example): the words cost far less in a fresh session, which does not carry that
large context.

1. Run collect (steps 1 to 3), then copy `writer-handoff.md` (beside this file) to the scratch folder
   and fill in every `<...>`: the inputs, the facts the logs do not show (step 4), and the lesson
   numbering.
2. From a new empty folder, launch the writer in the background:
   ```
   claude -p "Read <scratch>/writer-handoff.md and do exactly what it says." --model <opus model> \
     --setting-sources "" --disable-slash-commands --strict-mcp-config --no-session-persistence \
     --allowedTools "Read,Write,Edit,Bash" --add-dir <scratch> ${CLAUDE_PLUGIN_ROOT}/skills/worktreereview \
     --output-format json > <scratch>/run.json
   ```
3. When it ends, read `run.json` for its result and cost, check the page's figures against its tables,
   and carry on from step 7.

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
- The closing-pass field lists the passes after the closing one, but not a merge done by hand:
  `merge-unit-local.sh` records only its own merges. Check `git log` on main (step 4) for a
  merge of the unit after its closing pass, and say so in the report.

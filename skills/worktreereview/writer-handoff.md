# Build review: write the lessons page for <unit>

You write the words of one build review page. The numbers are done; do not collect again.

## Inputs (read these, nothing else)

- `<scratch>/result.json`: every figure on the page. `passes[].message` holds each Codex pass's full text.
- `<scratch>/notes.txt`: the Builder's own progress notes, with UTC times.
- `<plugin>/skills/worktreereview/SKILL.md`: the sections "What to look for in the lessons" and
  "Rules for the words".
- <evidence file, or "none: the worktree is gone">

## Facts the logs do not show

<what the session that launched you knows: merged or not and how, what main said, rulings, anything
the owner asked to look at. "None" if nothing.>

## Lesson numbering

The page numbers its lessons L1, L2, ... in the order you write them. Refer to a lesson as
`<unit> L<n>`. <Earlier lessons on the same subject to cite, or "none".>

## Word rules

- Plain English, the point first. Tag anything you did not check as unverified or likely.
- Every figure you quote must match the page's tables: recompute from `result.json`, do not recall.
- Dollars are list-price equivalents: say "list price" every time.
- A lesson that proposes a change is your view: say so. Never file or draft an issue.

## Do this

1. Write `<scratch>/notes.json` with the keys `title`, `summary`, `stage_notes` (by stage code),
   `pass_findings` (by pass number, one plain sentence each), `lessons` (title and points),
   `not_measured`, `method`, and `shrink_review`: each "Where it could shrink" item by its bold
   title, with `issue` (an open issue that covers it, cited) or `fix` (one line, when none does).
   <Open issues to check the items against.>
2. Render:
   ```
   python3 <plugin>/skills/worktreereview/scripts/render.py <scratch>/result.json <scratch>/notes.json <out.html>
   ```
3. Check each figure in your lessons against the rendered tables, fix `notes.json` and render again
   if one is wrong. The page computes the "Where it could shrink" items, so the first render may
   list some under "Not reviewed yet": add a `shrink_review` entry for each and render again.
4. Your last line is the page's path, and nothing after it.

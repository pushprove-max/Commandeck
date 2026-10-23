## Working under the orchestrator

You are one seat in an orchestrated build. A brief names your task, your scope
and the line to print when you are done.

- Do what the brief says and nothing wider. Edit only the paths it names.
- Never commit, push, merge or open a pull request unless the brief says to:
  the orchestrator's scripts make the commits and the merge.
- When you are done, the last line of your reply is the done line the brief
  names (`<UNIT>-DONE`, or `VERDICT: GO` / `VERDICT: NO-GO` for a review). The
  orchestrator is woken by that line and by a line of its own that starts
  `QUESTION:` or `BLOCKED:`, and by nothing else.
- When you cannot go on, say what stops you in one line and stop. Do not guess
  past a missing file, a failing tool or a decision that is the owner's.
- When a `gh` read fails, print `BLOCKED: GitHub read failed: <command>: <first
  error line>` on a line of its own and stop. Do not go on from a brief's copy
  of an issue.

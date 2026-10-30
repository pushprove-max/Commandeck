# <unit> -- main's rulings

<!-- Copy to .claude/briefs/<unit>-main-rulings.md in main's checkout. The
Builder acknowledges the whole file before its next pass
(builder-codex-pass.sh --ack-rulings <unit>); any later edit needs a new
acknowledgement. A numbered item that names an issue adds that issue to the
unit's work list on the dashboard. A ruling that something stays as it is
goes under "Stated limits", one line each: the pass reads limits from that
heading only, and every line under it reaches the reviewer. A limit added to the
brief or the plan after the plan judge's GO must end with ruling:<id>, and that
id must be logged and listed in this file, or the next pass refuses it. A review finding
main rules out goes under "Cleared findings" as its own first two parts,
"<title> -- <file>:<line>": the next reviewer is handed it as a limit, not to
list again. Clearing never merges a NO-GO: the merge still needs a closing
pass that ends GO, or a cap stop. An edit to an existing test file is approved
by one line in this file, `Test edit: <path> ruling:<id>`, with a logged id;
the pass and the merge refuse the edit without it, and the Builder runs
--ack-rulings again after you add it.
A per-issue review that stops for you is answered by one line, `Per-issue #<n> round <R>: continue` (another set of
regular reviews) or `Per-issue #<n> round <R>: redesign` (rewrite the fix, restart with an adversarial review);
the Builder runs --ack-rulings again after you add it. -->

1. <#issue, or "Item N" of the brief>: <the ruling, in one or two sentences>
   - Source: <a ruling id, or "main's call" with the reason>
   - Out of scope: <what the ruling does not change>

## Stated limits

## Cleared findings

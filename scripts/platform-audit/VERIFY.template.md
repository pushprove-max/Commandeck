# Verify one area's audit findings: {{SLICE}}

An automated auditor reviewed part of this project and wrote the findings in
`{{A}}/out/{{SLICE}}.md`. Its claims are UNVERIFIED. Your job: check every finding in that file against
the code and decide whether it is real. You change nothing in the code.

- Code (read-only copy, commit {{COMMIT}}): `{{A}}/src`. File paths in the findings are relative to it.
- Open GitHub issues (for duplicates): `{{A}}/open-issues.json` (number, title, body excerpt, milestone).
  Search it with Grep; you have read tools only.

For EACH finding (every ID, P1, P2 and P3):
1. Read the cited code and enough around it (callers, middleware, config, infra) to decide. Try hard to DISPROVE it:
   look for a guard elsewhere, a config that disables the path, a caller that cannot reach it, a test that pins the
   behaviour on purpose, or a comment recording a deliberate decision.
2. Verdict: `CONFIRMED` (the code does what the finding says and the risk is real), `PARTLY` (real, but narrower or
   different than claimed: say how), or `REFUTED` (say exactly what disproves it, with file:line).
3. Severity after checking: P1 = realistic trigger and material harm (security, data loss, legal, money); P2 = real
   defect or standards gap a customer or auditor would hit; P3 = minor. Say if you changed it.
4. Duplicate: the open issue number if one already covers it, else `new`.
5. A deliberate decision recorded in code comments (for example an owner's ruling) is not a defect:
   mark it `REFUTED (deliberate: <ruling>)` unless the finding shows the decision causes harm it did not consider.

Your final message is your verdict, saved for you: write ONLY this Markdown as it, ending with the counts line.

# {{SLICE}}: verification
| ID | Claimed | Verdict | Severity now | Duplicate | Evidence (file:line) and one-sentence reason |
|---|---|---|---|---|---|
One row per finding, in the file's order. Then:
## Notes
Anything a later fixer must know (for example two findings with one root cause).
Counts line: `confirmed=<n> partly=<n> refuted=<n> duplicates=<n>`

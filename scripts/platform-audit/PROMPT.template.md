# Best-practice audit: {{SLICE}}

You are auditing one part of this project. The code is a read-only copy at {{SRC}} (commit {{COMMIT}}).

## Your part
{{DESC}}

Where to look (start here, and follow imports into anything else this part depends on):
{{PATHS}}

## The question
Where does this part NOT follow established best practice or published standards, or reinvent something a standard
library, platform feature or well-known service already does well? Example of the kind of finding wanted: SMS code
autofill was hand-built as six separate inputs each marked one-time-code, while the standard is one real input
(the input-otp pattern) plus WebOTP and a managed verify service.

Standards and references to check against (use your own knowledge of them; cite the exact section or rule):
{{STANDARDS}}

The approved library or managed service for each area is in `.claude/paved-road.md` in the copy; a hand-built
version of something its row names is a finding.

## Rules
- Read the code. Every finding cites file:line from the copy and names the standard or practice it misses.
- Only real gaps you can see in the code. No style nits, no "consider adding tests" without a concrete risk.
- Say how sure you are: confirmed (seen in code), likely (strong signal, one step unverified), or possible.
- Severity: P1 = realistic trigger and material harm (security, data loss, legal, money); P2 = real defect or
  standards gap a customer or auditor would hit; P3 = minor or hygiene.
- Do not edit anything. Do not run builds or tests. Read only.
- Coverage: list every directory and main file you reviewed, and anything in your paths you could NOT review.

## Output (write ONLY this, as Markdown, as your final message)
# {{SLICE}}
## Summary
Three to five sentences: overall state and the biggest gaps.
## Findings
A table with exactly this header row and separator, then one row per finding, its ID {{ID}}-01, {{ID}}-02, ...:
| ID | Severity | Confidence | What we do (file:line) | Standard / best practice (cited) | Gap and risk | Recommended fix |
|---|---|---|---|---|---|---|
Recommended fix: prefer the standard library, platform feature or managed service. Order by severity, then
confidence. Only the table goes here (with no findings, the header row alone): a finding outside it, or a header
row that differs from the one above, gets no verdict and fails the audit.
## Reinvented wheels
Places where we hand-built something a standard, library or managed service covers; name the replacement.
## Coverage
Reviewed: ... / Not reviewed: ...

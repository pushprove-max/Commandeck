---
name: file-issue
description: Turn the owner's idea, bug or request into a complete GitHub issue (never their words verbatim), asking only about missing requirements; files when told. Use for "add to GitHub", "file an issue", "track this", or a rough feature description.
disable-model-invocation: true
allowed-tools: Bash(gh issue create *)
---

# File an issue

The owner's raw ask is input, not the issue. The GitHub issue must stand alone
for whoever implements it months later.

## 1. Rewrite, don't transcribe

Draft the issue with:

- **Title**: imperative, specific, under about 70 characters, no internal jargon.
- **What and why**: the user-visible behavior and the reason it matters.
- **Acceptance criteria**: verifiable bullets, each checkable by a
  walkthrough or test.
- **Out of scope**: what this issue deliberately does not change.

## 2. Clarify material gaps

Ask only when the request leaves a material requirement unresolved, then fold
the answer into the draft. Routine wording and title choices do not require
another approval round.

## 3. File when told

If the owner already asked to file, add to GitHub, or track the issue, publish
the completed draft with `gh issue create` without asking again. A request to
draft an issue does not authorize publishing it.

Report the URL. Never start implementing as part of this flow.

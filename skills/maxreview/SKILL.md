---
name: maxreview
description: Run an on-demand whole-branch Codex review outside a Builder unit. One adversarial pass, then review rounds until one finds no P0-P2 finding (at most 10), fixing and committing after every round. Use when the owner says "/maxreview" or asks for a max review of the current branch.
disable-model-invocation: true
---

# Whole-branch review

A whole-branch review that uses the same wording as the Builder review passes. The wording is never
hand-written: `wording.sh` reads it live from `scripts/builder-codex-pass.sh`, so it cannot drift.

## Wording

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/maxreview/wording.sh adversarial   # the angles
bash ${CLAUDE_PLUGIN_ROOT}/skills/maxreview/wording.sh review        # the closing focus
```

Each prints its text, then the "list every finding you can defend" line, the standing checks and one
severity line. If it exits non-zero (no pass script, or its wording markers or variables are gone), stop
and tell the owner. There is no hand-written fallback.

## Loop

1. Pick `<BASE>`, the one base the whole run reviews against (the branch's merge base with main). Work only on
   committed code; commit before each round. Never push.
2. Round 1 is the adversarial pass. Every later round is the review pass. Every round, not only the first, runs
   `node codex-companion.mjs adversarial-review --base <BASE> "<focus>"`, with `<focus>` the output of the
   matching `wording.sh` call. The plain `review` command takes no focus text and would drop the Builders' wording.
   `codex-companion.mjs` is the newest `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs`.
3. Proof bar at intake: a finding with no exact failing input or command is dropped, and does not hold convergence.
4. Fix each kept finding, run the tests that cover it, and commit. Then start the next round.
5. A fix that would change anything users see must stop and ask the owner, with a before and after. Do not apply it until the owner answers.
6. Stop when a round finds no P0, P1 or P2 finding, or after 10 rounds. After round 10 with findings left, say so.

## Fast lane

A Fast-lane worktree keeps using `scripts/fast-lane.sh review`; this skill does not replace it there.

## Record

On convergence, write `maxreview-r<N>-reports.md` (`<N>` the last round) with each round's findings and what
was done about each, ending with the single line `VERDICT: GO`. Without convergence, write no such line.

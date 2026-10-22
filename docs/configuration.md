# Roles and configuration

A unit starts with a batch brief and acceptance criteria. Main chooses a
planning tier with you. Planning seats write and judge the plan; you give
the build its go. A Builder works in the unit's worktree, gathers facts with
helpers, implements and runs the configured review loop. It fixes findings
and leaves evidence. Main checks the proof, runs the merge check on the
squashed tree and merges locally. The relay brings decisions to you.

[`config/routing.json`](../config/routing.json) is the default routing file.
It owns launch templates, agent types, model families and effort. A model
family is resolved at launch; available model ids depend on the account.
A null effort is omitted from the command.

| Role | Default agent / model | Effort | `/plugin` config keys | Can be off |
|---|---|---|---|---|
| orchestrator | Claude / opus | omitted | `orchestratorModel`, `orchestratorEffort` | no: it is the session that runs everything |
| plan-author | Claude / opus | high | `planAuthorModel`, `planAuthorEffort`, `planAuthorEnabled`, `planAuthorFast` | yes: no plan |
| plan-judge-sol | Codex / sol (Claude: sonnet) | high | `planJudgeSol` + `Agent`, `Model`, `Effort`, `Enabled`, `Fast` | yes |
| plan-judge-astra | Codex / astra (Claude: sonnet) | high | `planJudgeAstra` + `Agent`, `Model`, `Effort`, `Enabled`, `Fast` | yes |
| builder | Claude / opus | medium | `builderModel`, `builderEffort` | no: no branch to review or merge |
| fixer | Claude / opus | high | `fixerFirstModel`, `fixerFirstEffort`, `fixerModel`, `fixerEffort`, `fixerEnabled` | yes: every fix pass runs as the Builder was launched |
| codex-reviewer | Codex / sol (Claude: sonnet, headless) | medium | `codexReviewer` + `Agent`, `Model`, `Effort`, `Fast` | no: the merge check needs its GO |

Each role setting is a key in `/plugin` config. A per-launch pin
(`seat.sh --model/--effort`, `builder-launch.sh --effort`) beats the key, and
the key beats routing's default. `project`, the default, is no answer. A value
the role does not take is refused, naming the key. Setup writes the keys
from its answers (`--option <key>=<value>`). The keys live in your user
settings file, so a plugin update does not change them.

The fixer runs the fix passes after a review. The first one runs on the model
and effort the Builder was launched with (`fixerFirstModel=builder`, the
default); the later ones run on Opus high. The reviewer and both judges can
run on Claude (`<role>Agent=claude`): a Claude reviewer or judge cannot write.
The Claude-only profile sets those three agent keys to `claude`.

A helper is a built-in subagent type: `Explore` (Haiku) for search and lookup,
`general-purpose` (Sonnet) for edits, tests and judgment. The model guard
fills those models in, and asks for a type when a call names none.

| Location | Owns |
|---|---|
| `.claude/commandeck.json` | Project answers, schema version 1. |
| `.claude/settings.json` | Shared project workflow and selected cache settings. |
| `.claude/settings.local.json` | This machine's project permissions; each worktree also has its own settings. |
| `~/.claude/settings.json` | Machine-scope permissions when chosen; optional auto-mode entries and status line; the plugin's `/config` options (`pluginConfigs`), which setup fills where they are empty. A `/config` option beats the project's answer, and the doctor names where each value comes from. `maxBuilders`, the most Builders that may run at once over all units, is set there or by hand as `builder.maxBuilders` in the project's `commandeck.json`; setup asks nothing for it. `wakeKinds`, the Orca message types that wake main (default `worker_done,escalation,question,decision_gate,merge_ready`; others are held and shown at the next wake), and `wakeWindowSeconds`, the window in which actionable messages wake main once (default 60; 0 wakes at once), are set there too; setup asks neither. |
| `~/.claude/CLAUDE.md` | Optional marked global instruction blocks. |
| `~/.codex/hooks.json`, `~/.codex/config.toml` | Codex hooks and trust, relocated when CODEX_HOME is set. |
| `~/.commandeck/install/` | Per-project and machine manifests, original blobs and saved dashboard bind/port/hosts. |
| `~/.commandeck/plugin` | Stable link to the plugin folder setup last applied. |

Use setup to change answers. Its project keys include `profile`, `testCommand`,
`strictHooks`, `serena`, `standardContext`, `builder.clearLine`, `issueSizing`,
`chiefOfStaff`, `ponytail`, `cacheTtl`, `autoMode`, `workerSkillsOff`,
`workerPluginsOff`, `keeps` and `reviewLoop`. Role settings are `/plugin` keys
only: 0.26.0 reads no `builder.model`, `builder.effort`, `planModels`,
`planFast`, `codexModels` or `codexFast` an older setup saved there.

Review-loop keys are `maxRounds`, `closingPass`, `smallBuild`, `maxReviewMinutes`,
`maxTestPercent` and `maxUsd`. Setup saves tuned numeric answers as strings.
Defaults are no cap, a closing pass, one reviewer below 200 changed lines,
and report flags at 30 review minutes, a third of the clock on tests/idle
with over 10 minutes, and $30. Those report flags do not block a merge.
`generatedFiles` lets merge accept a tail of commits changing only the listed
generated paths after the reviewed commit; do not list handwritten source.

Set `COMMANDECK_ROUTING` in the launching environment to use your own routing
file instead of editing the installed copy. Project Builder and review answers
still apply. Other useful overrides are `COMMANDECK_MAIN`,
`COMMANDECK_WORKSPACES`, `COMMANDECK_SCRATCH` and `CODEX_HOME`. Git decides the
primary checkout from inside a linked worktree. The dashboard/report collector
also reads `COMMANDECK_CODEX_REVIEW_HOME`, default `~/.codex-review`, for review
spend; it does not itself change where reviewer processes run.

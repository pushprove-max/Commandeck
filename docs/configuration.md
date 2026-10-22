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

| Role | Default agent / model | Effort |
|---|---|---|
| orchestrator | Claude / opus | omitted |
| plan-author | Claude / opus | high |
| plan-author-second | Claude / fable | high |
| plan-judge-sol | Codex / sol | high |
| plan-judge-astra | Codex / astra | high |
| plan-judge-claude | Claude / sonnet, used without Codex | high |
| builder | Claude / opus | medium |
| codex-reviewer | Codex / sol | medium |
| claude-reviewer | Claude / sonnet, headless | high |
| design-coauthor | Claude / fable | high |
| audit-auditor | Codex / astra, headless platform audit | xhigh |
| audit-verifier | Claude / opus, headless platform verifier | omitted |
| lean-worker | Claude / sonnet helper | medium |
| lean-checker | Claude / sonnet blind checker | high |

Fable planning falls back to another allowed Claude model when unavailable.
The Claude-only profile uses its Claude judge instead of the Codex plan
judges. Its stock code reviewer is Sonnet, distinct from the default Opus Builder.
A Builder model override can make both Sonnet; the scripts do not enforce
different families.

The three plugin agent definitions in `agents/` are `commandeck:helper`
(read-only fact gathering), `commandeck:lean-worker` (edits and checks) and
`commandeck:lean-checker` (blind criterion checks). They omit CLAUDE.md and
have narrow tool lists. The model guard fills missing lean-agent settings
from routing; the helper uses Sonnet when no model is named.

| Location | Owns |
|---|---|
| `.claude/commandeck.json` | Project answers, schema version 1. |
| `.claude/settings.json` | Shared project workflow and selected cache settings. |
| `.claude/settings.local.json` | This machine's project permissions; each worktree also has its own settings. |
| `~/.claude/settings.json` | Machine-scope permissions when chosen; optional auto-mode entries and status line; the plugin's `/config` options (`pluginConfigs`), which setup fills where they are empty. A `/config` option beats the project's answer, and the doctor names where each value comes from. `maxBuilders`, the most Builders that may run at once over all units, is set there or by hand as `builder.maxBuilders` in the project's `commandeck.json`; setup asks nothing for it. |
| `~/.claude/CLAUDE.md` | Optional marked global instruction blocks. |
| `~/.codex/hooks.json`, `~/.codex/config.toml` | Codex hooks and trust, relocated when CODEX_HOME is set. |
| `~/.commandeck/install/` | Per-project and machine manifests, original blobs and saved dashboard bind/port/hosts. |
| `~/.commandeck/plugin` | Stable link to the plugin folder setup last applied. |

Use setup to change answers. Its project keys include `profile`, `testCommand`,
`strictHooks`, `serena`, `standardContext`, `builder.model`, `builder.effort`,
`builder.clearLine`, `issueSizing`, `chiefOfStaff`, `ponytail`, `cacheTtl`,
`autoMode`, `workerSkillsOff`, `workerPluginsOff`, `keeps`, `planModels`,
`planFast`, `codexModels`, `codexFast` and `reviewLoop`.

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

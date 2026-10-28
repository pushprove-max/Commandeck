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
| orchestrator | Claude / opus | medium | `orchestratorModel`, `orchestratorEffort` | no: it is the session that runs everything |
| plan-author | Claude / opus | high | `planAuthorModel`, `planAuthorEffort`, `planAuthorEnabled`, `planAuthorFast` | yes: no plan |
| plan-judge-sol | Codex / sol (Claude: sonnet) | high | `planJudgeSol` + `Agent`, `Model`, `Effort`, `Enabled`, `Fast` | yes |
| plan-judge-fable | Claude / fable | high | `planJudgeFable` + `Model`, `Effort`, `Enabled`, `Fast` | yes |
| builder | Claude / opus | medium | `builderModel`, `builderEffort` | no: no branch to review or merge |
| fixer | Claude / opus (first fix round: the Builder's) | medium | `fixerFirstModel`, `fixerFirstEffort`, `fixerModel`, `fixerEffort`, `fixerEnabled` | yes: every fix pass runs as the Builder was launched |
| codex-reviewer | Codex / sol (Claude: sonnet, headless) | medium | `codexReviewer` + `Agent`, `Model`, `Effort`, `Fast` | no: the merge check needs its GO |

Each role setting is a key in `/plugin` config. A per-launch pin
(`seat.sh --model/--effort`, `builder-launch.sh --effort`) beats the key, and
the key beats routing's default. `project`, the default, is no answer. A value
the role does not take is refused, naming the key. Setup writes the keys
from its answers (`--option <key>=<value>`). The keys live in your user
settings file, so a plugin update does not change them.

One order decides every value setup saves: this run's explicit answer (a flag
or `--option`), then the profile or `--recommended`, then the value saved
before. When a run moves the reviewer or the Sol judge to the other agent and
names no model for it, a saved model that agent cannot run goes back to the
default, and setup says so.

The fixer runs the fix passes after a review: the first one on the model and
effort the Builder was launched with, every later one on Opus medium by default.
`fixerFirstModel=opus` and `fixerFirstEffort=medium` run the first one on Opus
medium too. The reviewer and the Sol judge can
run on Claude (`<role>Agent=claude`): a Claude reviewer or judge cannot write.
The Claude-only profile sets those two agent keys to `claude`. The Fable judge
always runs on Claude and has no agent key.

A helper is a built-in subagent type: `Explore` (Haiku) for search and lookup,
`general-purpose` (Sonnet) for edits, tests and judgment. The models come from
`roles.builder.helpers` in `config/routing.json`. Every worker pane runs the
model guard: it fills those models in, and asks for a type when a call names
none. Builder, plan-author and fix-round panes enforce them, except that a
`general-purpose` call there may name the search model (in any case, or as a
full model id) and keeps it. Plan-author panes may start helpers; plan-judge and
reviewer panes may not: Codex judge and reviewer seats launch with sub-agents
off, and Claude ones have `Agent` denied.

The Codex helper, `scripts/codex-ask.sh [--timeout <s>] '<question>'`, is a
read-only second opinion for Builder, plan-author and fix-round panes; judge and
reviewer panes are refused. It runs the model the Codex reviewer route names
(`codexReviewerModel`), in a read-only sandbox from a temporary folder under
`/tmp`, and prints the model that answered above the answer. A temporary folder
inside the repository or any of its worktrees is refused, and no rules files are
loaded. A setup whose reviews run on
Claude has no Codex helper. The deadline is `--timeout` seconds (default 300,
1 to 1800), then a kill 2 s later; the answer is cut at 6000 bytes. Every call
is a row in `.claude/metrics/codex-helper.jsonl` of the main checkout, and the
build review counts them.

| Location | Owns |
|---|---|
| `.claude/commandeck.json` | Project answers, schema version 1. |
| `.claude/settings.json` | Shared project workflow and selected cache settings. |
| `.claude/settings.local.json` | This machine's project permissions; each worktree also has its own settings. |
| `.claude/settings.local.json` of the main checkout | Claude Code applies it over every worktree session's own settings, so setup puts no lean list there. |
| `.claude/main-session.settings.json` of the main checkout | Main's lean lists: the `ui-themes` and `mattpocock-skills` plugins off. Only a session started with `claude --settings .claude/main-session.settings.json` reads it, so start main that way; workers never do. A key you set there stays; uninstall removes only what setup added. |
| `~/.claude/settings.json` | Machine-scope permissions when chosen; optional auto-mode entries and status line; the plugin's `/config` options (`pluginConfigs`), which setup fills where they are empty and replaces with this run's answers. A `/config` option beats the project's answer, and the doctor names where each value comes from. `maxBuilders`, the most Builders that may run at once over all units, is set there or by hand as `builder.maxBuilders` in the project's `commandeck.json`; setup asks nothing for it. `wakeKinds`, the Orca message types that wake main (default `worker_done,escalation,question,decision_gate,merge_ready`; others are held and shown at the next wake), and `wakeWindowSeconds`, the window in which actionable messages wake main once (default 60; 0 wakes at once), are set there too; setup asks neither. |
| `~/.claude/CLAUDE.md` | Optional marked global instruction blocks. |
| `~/.codex/hooks.json`, `~/.codex/config.toml` | Codex hooks, trust, the notify line and `check_for_update_on_startup = false` (no update prompt in launched panes; an owner's own value stays), relocated when CODEX_HOME is set. |
| `~/.commandeck/install/` | Per-project and machine manifests, original blobs and saved dashboard bind/port/hosts. |
| `~/.commandeck/plugin` | Stable link to the plugin folder setup last applied. |

Use setup to change answers. Its project keys include `profile`, `testCommand`, `typecheckCommand`, `screenPaths`, `lockfileDeny`,
`strictHooks`, `serena`, `standardContext`, `builder.clearLine`, `issueSizing`,
`chiefOfStaff`, `trustAllHooks`, `mainCacheTtl`, `workerCacheTtl`, `autoMode`, `workerSkillsOff`,
`workerPluginsOff`, `keeps`, `reviewLoop` and `autoDecideNever` (your own list of decisions
that auto-decide never makes for you; setup never asks for it and keeps it on a re-run). Role settings are `/plugin` keys
only: 0.26.0 reads no `builder.model`, `builder.effort`, `planModels`,
`planFast`, `codexModels` or `codexFast` an older setup saved there.

`autoDecideSeats` is a `/plugin` key: `chiefOfStaff` (default), `chiefOfStaff,main` or `off`. It names the seats
that have `/autodecide`, the band and the rules; a seat not listed never reads the mode. A change applies to the
next session. With both seats listed, they share one mode: `/autodecide on` or `off` in one seat shows in the other
seat's band and status line within 5 seconds.

Review-loop keys are `blockAt`, `passCap`, `freshClosing`, `closingPass`, `smallBuild`, `maxReviewMinutes`,
`maxTestPercent` and `maxUsd`. Setup saves tuned numeric answers as strings.
Defaults are P2 as the lowest severity that holds a merge, a pass cap of 5, a
fresh closing reviewer, a closing pass, one reviewer below 200 changed lines,
and report flags at 30 review minutes, a third of the clock on tests/idle
with over 10 minutes, and 30 US dollars. Those report flags do not block a merge.
From the pass cap on the record, `review` runs as the closing pass
([Review passes](review-loop.md)). `maxRounds` is no longer read.
`generatedFiles` lets merge accept a tail of commits changing only the listed
generated paths after the reviewed commit; do not list handwritten source.

Set `COMMANDECK_ROUTING` in the launching environment to use your own routing
file instead of editing the installed copy. Project Builder and review answers
still apply. Other useful overrides are `COMMANDECK_MAIN`,
`COMMANDECK_WORKSPACES`, `COMMANDECK_SCRATCH` and `CODEX_HOME`. Git decides the
primary checkout from inside a linked worktree. The dashboard/report collector
also reads `COMMANDECK_CODEX_REVIEW_HOME`, default `~/.codex-review`, for review
spend; it does not itself change where reviewer processes run.

If main runs in another project's checkout and drives this repo's units from
there, install the watcher with `COMMANDECK_MAIN_PANE_DIR` set to that checkout
(`COMMANDECK_MAIN_PANE_DIR=<path> scripts/main-watch.sh --install`). Without it
the watcher finds no main pane, and no finished seat ever wakes main.

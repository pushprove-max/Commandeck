# Plan: role-cut-plugin-2026-10-22

Tier: Standard. LOCAL merge only. Changed-file tests only (the test files this build edits), no red proofs, no
test-timeout raises. Issues 312, issue 313. Batch brief: `.claude/briefs/role-cut-plugin-2026-10-22-batch.md`.

Keep (routing names, no renames): `orchestrator`, `builder`, `codex-reviewer`, `plan-author`, `plan-judge-sol`,
`plan-judge-astra`, new `fixer`. Delete: `audit-auditor`, `audit-verifier`, `claude-reviewer`, `design-coauthor`,
`lean-checker`, `lean-worker`, `plan-author-second`, `plan-judge-claude`. Every agent file the plugin ships goes:
`agents/helper.md`, `agents/lean-worker.md`, `agents/lean-checker.md` (the `agents/` folder is then empty and
removed).

## Decisions (ponytail ladder: rung stopped at, lazier option rejected)

1. Fixer is not a new pane: rung 2, the existing fix-round step-up in `scripts/builder-fresh-round.sh:74-84`
   (issue 289) becomes the fixer rule. Rejected lazier: leave the issue-289 rule as is; it sets no effort, has no
   first-pass override and no config, so it fails issue 313.
2. Fix-pass count = number of `<unit>-fix-r*.md` hand-offs in the unit's briefs folder: rung 2, files the pass
   already writes. Rejected lazier: the `N` in `fix-r<N>` (today's rule); `N` is the pass number, so a GO on
   pass 1 then NO-GO on pass 2 would count as a second fix pass. Per-unit files make the count reset per build.
   The count is taken only when the hand-off itself is a fix hand-off (section 3).
3. One settings surface: every role setting is a `/plugin` `userConfig` key, read by one reader
   `pp_role_option` on top of `pp_config_option` (`scripts/paths.sh:727`). Setup writes those keys and nothing
   else for a role. Rejected lazier: options pickers alone; a hand-edited `settings.json` would pass an invalid
   value silently, which issue 312 forbids.
4. Accepted values come from fixed lists in `PP_ROUTE_JQ`, not from the roles routing happens to name: Claude
   models `opus`, `sonnet`, `fable` (today's `builderModel` options); Codex models a family (`sol`, `astra`, any
   `^[a-z]+$` the account lists, resolved by `pp_codex_model`) or an exact id `^gpt-[0-9.]+-[a-z]+$`; efforts the
   existing `efforts` list. Rejected lazier: keep `def aliases` (`paths.sh:464`) derived from rows; after the cut
   it would hold only `opus` and refuse `sonnet` everywhere.
5. Agent keys only where there is a real choice: `codex-reviewer`, `plan-judge-sol`, `plan-judge-astra`
   (codex | claude). The other four roles run one agent; a one-option agent key would be a setting that does
   nothing. The Claude choice carries the read-only overlay `plan-judge-claude` and `claude-reviewer` carried
   today (section 4).
6. On/off keys only where OFF has a meaning: `plan-author`, `plan-judge-sol`, `plan-judge-astra`, `fixer`.
   `orchestrator`, `builder`, `codex-reviewer` cannot be off (reasons in section 4); setup refuses an OFF answer
   for them naming the reason, and no key exists that could set it.
7. The Claude-only profile stays: `setup.sh --profile claude` writes `codexReviewerAgent=claude`,
   `planJudgeSolAgent=claude`, `planJudgeAstraAgent=claude`, and the Codex requirement is skipped as today. The
   profile is a setup answer that sets keys, not a second place a reader looks.
8. `--risky` stays, only as the merge gate's three-reviewer trigger; its design pane goes.
9. The agent-model guard keeps its model fill (Explore -> Haiku, general-purpose -> Sonnet) and its nudge is
   repointed to the built-in types; the builder-search guard already routes to `Explore` and is kept, with tests.
10. OFF is enforced where a seat launches (`seat.sh launch|run`), and `plan-tier.sh` prints the visible skip.
11. In-pane `/effort`: the Builder's first step is the `seat.sh effort` check (section 3); its result picks
    in-place switching or a fresh fixer seat for pass 2+.
12. `pp_argv` and the `claude-headless` template stay: the Claude choice of `codex-reviewer` runs headless on
    them. `codex-headless` (`config/routing.json:7`) goes only if, after the deletions,
    `rg -n 'codex-headless' scripts hooks config` shows no caller.

## 1. Reference map (deleted roles and agents)

Command (evidence): `for n in audit-auditor audit-verifier claude-reviewer design-coauthor lean-checker
lean-worker plan-author-second plan-judge-claude commandeck:helper 'agents/helper'; do rg -n --hidden
-g '!CHANGELOG.md' -g '!.git' -g '!.claude/plans/**' "$n" .; done`. The one exception is history: CHANGELOG and
the committed plans under `.claude/plans/` (four older plans name these roles, e.g.
`.claude/plans/commandeck-plugin-sync-2026-10-17.md:63`) stay untouched. Every other hit is below, with the action.

### All rows
- `config/routing.json` rows: `plan-author-second` ~29-37, `plan-judge-claude` ~57-66, `claude-reviewer` ~85-93,
  `design-coauthor` ~94-101, `audit-auditor` ~102-110, `audit-verifier` ~111-118, `lean-worker` ~119-126,
  `lean-checker` ~127-134: delete. Their Claude fields move to the kept rows' `claude` overlay (section 4). Notes
  of `plan-judge-sol` ~45 and `plan-judge-astra` ~55: drop the "plan-judge-claude instead" sentences; astra's
  "reads both plans ... for the merge" -> "reads the plan".
- `docs/configuration.md` ~19, 22, 25-30 (table rows): delete; ~33-36 (Claude judge, Sonnet reviewer prose):
  rewrite as the `claude` choice of the reviewer and judges; ~38-42 (the three agent definitions): replace with
  one line: helpers are the built-in `Explore` (Haiku, search and lookup) and `general-purpose` (Sonnet,
  judgment); add the `fixer` row and the per-role `/plugin` keys table (section 4).
- `scripts/codex-helpers.sh` ~48 (`design-coauthor`), ~51 (`plan-author-second`, `plan-judge-claude`), ~54
  (`claude-reviewer`), ~58 (`audit-auditor`, `audit-verifier`): delete those keys from `ROLE_LANES`.
  `"fixer": "fixing"` (~57) already exists.

### audit-auditor, audit-verifier (path deleted)
- `scripts/platform-audit/` whole folder: `run-audit.sh`, `run.sh`, `verify.sh`, `select-areas.py`,
  `PROMPT.template.md`, `VERIFY.template.md`: delete.
- `scripts/__tests__/platform-audit.test.sh`: delete.
- `templates/paved-road.md` ~15-25 (the audit paragraph and the `.claude/paved-road-areas.tsv` format, read only
  by `select-areas.py`): delete. The registry itself stays (read by `builder-codex-pass.sh:122` and
  `setup.sh:487`). Check `rg -n 'paved-road-areas'` is empty after.
- `templates/test-audit*` is a different feature (test audit): untouched.

### claude-reviewer (its job moves to `codex-reviewer`'s `claude` choice)
- `scripts/builder-claude-pass.sh` (11 lines, sets `COMMANDECK_PASS=claude`): delete; the pass now reads its agent
  from `pp_pass`.
- `scripts/builder-codex-pass.sh` ~56-63 (comment): rewrite for "the reviewer's agent is `codexReviewerAgent`";
  ~73-75: `BY=${COMMANDECK_PASS:-$(pp_pass)}` (the env stays only as the self-test's switch); ~527 (message
  naming builder-claude-pass): name the key instead; ~732-736 (claude branch): read model/effort and argv from
  `pp_argv codex-reviewer` with the `claude` overlay, not `roles["claude-reviewer"]`.
- `scripts/paths.sh` `pp_pass` ~893-898: returns `pp_role_option codex-reviewer agent` (codex unless set);
  ~844-845 comment follows.
- `scripts/builder-launch.sh` ~9 and `scripts/worktree-setup.sh` ~243 (`builder-(codex|claude)-pass`): one
  script now, `builder-codex-pass`.
- `scripts/setup.sh`, `scripts/doctor.sh`, `scripts/update.sh`, `scripts/proof-run.sh`, `skills/setup/SKILL.md`,
  `docs/first-build.md` ~28, `docs/troubleshooting.md` ~15, `docs/proof-run.md` ~16: `--profile claude` and the
  Claude review answer STAY; only wording that names `claude-reviewer` or `builder-claude-pass` changes to "the
  reviewer on Claude".
- Tests: `scripts/__tests__/seat.test.sh` ~10 and `seat-run-refused.test.sh` ~34 launch `claude-reviewer` to prove
  a headless role is refused as a seat: rewire to `codex-reviewer` with `codexReviewerAgent=claude` (headless via
  the overlay). `install-lib.test.sh` ~431, `requirements.test.sh` ~66, ~71,
  `hooks/__tests__/dependency-addition-guard.test.sh` ~130, `fixtures/builder-launch-resume-setup.sh` ~19: keep
  the Claude-profile cases; replace only a `claude-reviewer` or `builder-claude-pass` name.
- Not this: `hooks/codex-dispatch.sh` ~37, ~59 and `docs/hooks.md` ~81 "Claude-only" mean hooks, not the profile.

### design-coauthor (path deleted; `--risky` kept, Decision 8)
- `scripts/builder-launch.sh` ~12-13 (comment), ~89-91 (second-call resume, design only), ~237 (`## Design check`
  text -> a one-line `## Risky launch` section: "three reviewers"), ~295-304 (note wait), ~352 (design-spec
  rollback), ~373-378 (design pane): delete the pane; one call opens the Builder.
- `scripts/builder-codex-pass.sh` ~351, ~365: read `## Risky launch` instead of `## Design check`.
- `scripts/paths.sh` `pp_unit_briefs` (~829) and `pp_unit_name` (~852): drop `-design(-spec)?` from the regexes.
- `docs/review-loop.md` ~7, ~41, `templates/AGENT_STARTUP.md` ~24, `templates/main-session.md` ~89,
  `templates/_builder-brief-template.md` ~132 and its `{design}` placeholder: drop the design pane/note.
- Tests: `builder-launch-resume-rollback.test.sh` ~26, ~45-48 (design pane cases): rewire to "a risky launch opens
  the Builder at once and its brief has `## Risky launch`". `to-main.test.sh` ~111 uses `COMMANDECK_SEAT=design-coauthor`
  as a non-builder seat value: rewire to `plan-author`. Builder greps tests for `## Design check` and rewires.

### helper, lean-worker, lean-checker (all agent files deleted; helpers are built-in types)
- `agents/helper.md`, `agents/lean-worker.md`, `agents/lean-checker.md`: delete.
- `hooks/agent-model-guard.sh`: ~5-17 (comment): rewrite to the built-in map; ~24-30 (`LEAN` lookup) and ~39
  (`$e` from lean): delete; ~36-37 map: `{Explore: "haiku", "general-purpose": "sonnet", debugger: "sonnet"}`
  (drop `commandeck:*`); ~41/~47 nudge: fires on an untyped call only (`$t == ""`, which would run as Opus), text
  "Name a subagent type: Explore (runs as Haiku) for search and lookup, general-purpose (runs as Sonnet) for
  judgment, edits or tests." A general-purpose call is no longer nudged (it is the target).
- `hooks/builder-search-guard.sh`: names no deleted agent; its refusals already route to `Explore` and an `Agent`
  call resets the streak (~32). Kept as is; tests added (section 2).
- `docs/hooks.md:18`: "Fills missing helper models (Explore -> Haiku, general-purpose -> Sonnet), forces Builder
  Explore calls to Haiku, and names a type for an untyped call; it never refuses the call."
- `hooks/__tests__/agent-model-guard.test.sh` ~54-56 (`commandeck:helper` case): delete; ~80-96 (lean and nudge
  cases): rewrite to the new nudge (section 2).
- `scripts/__tests__/plugin.test.sh` ~89-96 (helper.md frontmatter check): delete; ~97-100 (caps check): drop
  helper.md, keep the Builder-template half, and check `20th tool call` in the template (the cap moves there);
  ~101-107 (lean agent loop): delete. Add: "the plugin ships no `agents/` folder".
- `scripts/__tests__/subagent-usage.test.sh` ~46-53: sample subagent type -> `general-purpose`.
- `scripts/__tests__/version-check.test.sh:49` makes `agents/helper.md` in a temp repo: Builder reads the case;
  if it tests the agents folder, delete it, else use a kept path such as `skills/setup/SKILL.md`.
- `templates/_builder-brief-template.md` ~38-42: "A helper that searches or looks up is `Explore` (Haiku); one
  that edits, runs, tests or judges is `general-purpose` (Sonnet). Every helper prompt carries every fact and
  limit the helper needs, answers by its 20th tool call, and names what it did not find (`NOT FOUND: <what you
  searched, where>`)." `templates/main-session.md` ~147-148: same two types, drop the lean lines.

### plan-author-second, plan-judge-claude (Panel on the kept set)
- `scripts/plan-tier.sh` ~37 (Panel seats -> `plan-author plan-judge-astra plan-judge-sol`), ~43 and ~47 (second
  planner and its question): delete; ~45 `(as ...)` branch: delete (a seat runs as its own role, on its own agent).
- `scripts/paths.sh` `pp_plan_models`/`pp_plan_seat` ~802-822: the allow-list swap and the `plan-judge-claude`
  fallback go; `pp_plan_seat <role>` prints `<role> <agent> <model>` from `pp_role_option`. A judge on `codex`
  where Codex is not installed is REFUSED naming the role and the fix (`<role>Agent=claude`, or off).
- `scripts/seat.sh` ~110-113: the `RROLE` remap comment and line go (a seat keeps its own role; its agent comes
  from its key). Two judges both on Claude stay two seats, each with its own name, pane and record.
- `skills/setup/SKILL.md` ~131-134 (Plan models, fast tier): replaced by the per-role questions (section 4).
- `templates/main-session.md` ~59-75: Panel = `plan-author` plans, `plan-judge-astra` and `plan-judge-sol` judge,
  no second author, no merge step; drop the `plan-judge-claude` sentence (~73); one line: either judge may run on
  Claude by its agent key.
- Tests: `seat-run.test.sh` ~13-45, `seat-run-refused.test.sh` ~12-42, `seat-fence.test.sh` ~10-28,
  `seat-plan-marker.test.sh` ~62-82, `seat-launch.test.sh` ~17-55 use `plan-judge-claude` as the stock Claude
  seat. Rewire: cases about a read-only Claude judge -> `plan-judge-sol` with `planJudgeSolAgent=claude` (the
  overlay is what those cases prove); cases about seat mechanics only (launch phases, fence, marker) ->
  `plan-author`. `plan-tier.test.sh`: Panel cases expect three seats.

## 2. Subagent guards (Builders, Fixers and planners keep Haiku and Sonnet helpers)

| Guard | Who it covers | After the cut |
|---|---|---|
| `hooks/agent-model-guard.sh` (all panes, `Agent|Task`, `hooks.json:32`) | Builder, Fixer (same pane, `COMMANDECK_BUILDER=1`), planner seats | Explore unnamed -> haiku; general-purpose unnamed -> sonnet; named model kept (Builder Explore always haiku); untyped -> opus fill plus the type nudge; never refuses |
| `hooks/builder-search-guard.sh` (Builder worktrees only) | Builder, Fixer | refusals name `Explore`; an `Agent` call of either type resets the streak; a subagent's own search (`agent_id` set) is never counted |

Tests, `hooks/__tests__/agent-model-guard.test.sh` (each asserts the call is allowed and the filled model):
"a Builder's unnamed Explore runs as Haiku", "a Builder's Explore naming sonnet still runs as Haiku", "a Builder's
unnamed general-purpose runs as Sonnet and is not nudged", "a planner seat's (`COMMANDECK_SEAT=plan-author`, no
`COMMANDECK_BUILDER`) Explore and general-purpose run as Haiku and Sonnet", "an untyped call gets the type nudge",
"a `commandeck:helper` call is no longer special-cased (falls to opus like any unknown type)".
`hooks/__tests__/builder-search-guard.test.sh`: beside the Explore reset (~27) add "a general-purpose Agent call
resets the streak" and "a general-purpose subagent's search is never counted or refused".
Catch (the nudge): an untyped helper that would silently run on Opus.

## 3. issue 313 fixer

- Today: a NO-GO pass writes `<unit>-fix-r<N>.md` and starts `builder-fresh-round.sh`
  (`builder-codex-pass.sh:1185-1242`), which `/clear`s the Builder pane; `/clear` keeps the launched model and
  effort. `builder-fresh-round.sh:74-84` types `/model opus` when `N >= 2` and the record's model is not Opus,
  and appends `model=opus` to the seat record. The same script also takes GO continuations
  (`<unit>-after-r<N>.md`, `builder-codex-pass.sh:1205`) and added work (`builder-add-work.sh:44`).
- First Builder step, before any fixer code: the in-pane effort check. Open an idle Claude pane, run
  `seat.sh effort <handle> high` (the one `/effort` send, `seat.sh:192-212`), and confirm the pane's next turn runs
  at high (its transcript or status line); record command and result in the evidence. If it takes, pass 2+
  switches in place. If it does not, pass 2+ opens a fresh fixer seat instead: after the Builder pane settles,
  close it and relaunch the Builder seat on the same worktree with the fixer model/effort as per-launch pins
  (`seat.sh launch builder`, the path `builder-launch.sh` execs), handing it the fix hand-off; the record says
  `fixer=later:fresh-seat`. Pass 1 never needs a switch (it keeps the Builder's settings).
- Routing row `config/routing.json` (new): `"fixer": {agent: claude, model: opus, effort: high,
  first: {model: "builder", effort: "builder"}, unboxed: true, edits: true, note}`. `"builder"` = the build's
  launched Builder model/effort; `validate` takes the `first` object.
- Builder's launched model/effort: from the seat record `$REC` (`seat-<unit>-builder.txt`), last `model=` line
  else `--model` in `cmd=` (today's sed, ~77-78), and `--effort` in `cmd=` the same way; a per-build
  `builder-launch.sh --effort` raise is in that `cmd=`, so pass 1 follows it.
- Filename guard: the rule runs only when the hand-off's name is `<unit>-fix-r<N>.md`. A GO continuation, an
  added-work hand-off or any other file types no `/model` or `/effort` and appends no `fixer=` line, whatever fix
  files exist.
- Count: `K` = number of `<unit>-fix-r*.md` in the hand-off's folder (Decision 2).
- Rule in `builder-fresh-round.sh` ~74-84 (replaces the issue-289 block): `fixerEnabled` false -> type nothing
  (the pane keeps its launched model/effort every round). `K = 1` -> `pp_role_option fixer firstModel|firstEffort`,
  else routing `first`; `builder` means type nothing. `K >= 2` -> `pp_role_option fixer model|effort`, else
  routing (opus, high); type `/model <m>` and `seat.sh effort <h> <e>` only where the pane differs (or the fresh
  seat, per the check). An invalid value stops the hand-off with `fail`, naming the key.
- Record: append `model=<m>`, `effort=<e>`, `fixer=<first:builder|first:config|later:routing|later:config|later:fresh-seat|off>`
  to `$REC`, where issue 289 already writes `model=`. Dashboard (`dashboard/app.js` ~318-335) and the token panel
  read the seat's model/effort; builder confirms their producer takes the last `model=`/`effort=` line of the
  record and, if it reads only `cmd=`, rewires it to the last line.
- Setup: the Fixer question sits next to the Builder questions (section 4).
- Catches: a later fix round left on a weaker Builder model; a GO continuation or added work switched to the fixer
  model; a fixer seat the dashboard shows on the wrong model.
- Tests, `scripts/__tests__/builder-fresh-round.test.sh` (rewrite the issue-289 cases ~77-94):
  1. "first NO-GO on a build: the fixer keeps the Builder's launched model and effort, a raised Sonnet high
     Builder included, and the record says fixer=first:builder".
  2. "second NO-GO on the same build: the fixer types /model opus and /effort high; the record says model=opus
     effort=high fixer=later:routing".
  3. "a /plugin override wins for either pass: fixerFirstModel=opus on the first, fixerModel=sonnet
     fixerEffort=medium on the second".
  Plus "fixer off: no /model or /effort on any round", "a new unit's first fix round counts as first", and the
  filename guard: "two fix files exist, the pane is Opus high, fixerModel=sonnet fixerEffort=medium: an
  `<unit>-after-r3.md` GO continuation and an added-work hand-off type nothing and leave the record unchanged".

## 4. issue 312 `userConfig` per role

Precedence, the one order for every role setting: a per-launch pin (`seat.sh --model/--effort`,
`builder-launch.sh --effort`) > the `/plugin` key > routing's default. Every key uses `"project"` as default and
no-answer value (as `builderModel` does; `pp_config_option` skips it), so unset keeps today's routing value.

| Role | Keys | Reaches the launch via | OFF |
|---|---|---|---|
| orchestrator | `orchestratorModel`, `orchestratorEffort` | setup writes `model` (and `effortLevel` if the Builder confirms Claude Code reads it; else effort is shown by `doctor.sh` and named in evidence) to the project settings file setup already writes (`$SETTINGS`); `doctor.sh` flags a file that differs from the key | cannot be off: it is the session that runs everything |
| builder | `builderModel`, `builderEffort` (exist) | `pp_route_json` -> `builder-launch.sh` -> `seat.sh` | cannot be off: no branch to review or merge |
| codex-reviewer | `codexReviewerAgent`, `codexReviewerModel`, `codexReviewerEffort`, `codexReviewerFast` | `builder-codex-pass.sh` ~737-744 (codex) / `pp_argv` (claude); setup preflight `setup.sh:320` | cannot be off: `--verify` at merge needs a GO round file; off would block every merge or skip the review the gate needs |
| plan-author | `planAuthorModel`, `planAuthorEffort`, `planAuthorEnabled`, `planAuthorFast` | `pp_plan_seat` -> `pp_route_json` -> `seat.sh launch`; `plan-tier.sh` prints the seats | `seat.sh` refuses; `plan-tier.sh` prints `No plan` and the `--skip-plan --reason 'plan-author is off in /plugin config'` line |
| plan-judge-sol | `planJudgeSolAgent`, `planJudgeSolModel`, `planJudgeSolEffort`, `planJudgeSolEnabled`, `planJudgeSolFast` | as plan-author | `seat.sh` refuses; Plan + judge runs astra if on; Panel runs astra alone |
| plan-judge-astra | `planJudgeAstraAgent`, `planJudgeAstraModel`, `planJudgeAstraEffort`, `planJudgeAstraEnabled`, `planJudgeAstraFast` | as plan-author | `seat.sh` refuses; Panel runs sol alone |
| fixer | `fixerFirstModel`, `fixerFirstEffort`, `fixerModel`, `fixerEffort`, `fixerEnabled` | `builder-fresh-round.sh` (section 3) | no switch: every fix round keeps the Builder's launched model/effort |

- Both judges off: Plan + judge and Panel become One planner; the plan installs unjudged and plan-tier says so.
- Agent choice (Decision 5): the three rows get a `claude` overlay object: `codex-reviewer.claude` = the
  `claude-reviewer` row's fields (`model: sonnet, effort: high, headless: true, tools: [Write, Edit,
  NotebookEdit]`); each judge's `claude` = the `plan-judge-claude` row's (`model: sonnet, effort: high, tools:
  [Write, Edit, NotebookEdit]`). `PP_ROUTE_JQ` `seat(...)` takes an `$agent` argument: `claude` merges the overlay
  over the row, sets `agent: claude` and drops `sandbox`; `resolve` then computes `readonly` from `tools` as it
  does today (`paths.sh:547`). `validate` refuses a `claude` overlay without `Write` in `tools` (no Claude
  reviewer or judge that can write) and a model/effort outside the fixed lists. A Claude-chosen model key value
  (`planJudgeSolModel=opus`) replaces the overlay's model; a Codex family on a Claude agent is REFUSED naming the key.
- Reader: `pp_role_option <role> agent|model|effort|enabled|fast|firstModel|firstEffort` in `paths.sh` next to
  `pp_option` (~737): key from the role name in camelCase, value from `pp_config_option`, validated against the
  fixed lists for the role's effective agent; refusal text `REFUSED: /plugin config <key> = <v> is not a
  <claude|codex> <model|effort> for <role>`. `pp_route_json` (~774-788) applies model/effort for every role
  through it (today it does so for the Builder only, from `builder.*` in `commandeck.json` then `/config`).
- Codex model ids: a Codex role's model key takes a family or an exact id. `pp_codex_model` (~597-602) loses its
  `[role]` lookup of the project's `codexModels`; it resolves only the value handed in. Fast tier:
  `<role>Fast` replaces `codexFast` (codex-reviewer) and `planFast` (plan seats) in `pp_codex_fast` and
  `pp_route_json`'s `planFast`.
- Folded, no second way to set the same thing: setup.sh's `--builder-model`, `--builder-effort`, `--codex-model`,
  `--plan-models`, `--plan-fast` and `--codex-fast`/`--no-codex-fast` go, replaced by one repeatable value flag
  `--option <userConfig key>=<value>` (added to `TAKES` ~56), so setup's transport names exactly the keys
  `/plugin` shows. No `--fixer` flag. `commandeck.json` stops getting `builder.model`, `builder.effort`,
  `codexModels`, `planModels`, `planFast`, `codexFast` (`setup.sh:377-389`). On a rerun (and `update.sh`, which
  reruns setup), setup moves any such saved value into its key where the key is unset: `builder.*` ->
  `builderModel/Effort`; `codexModels[r]` -> `<r>Model`; `planFast` -> the listed seats' `Fast`; `codexFast` ->
  `codexReviewerFast`; a `planModels` that excludes a seat's default -> that seat's first allowed model of its
  agent, and no Codex model allowed -> both judges' `Agent=claude` (today's `pp_plan_seat` swap, made once).
  Readers no longer read those project fields; a leftover one makes `doctor.sh` print "move it: rerun
  /commandeck:setup". `pp_option` drops its project-file arms for `builderModel`/`builderEffort`; the non-role
  options keep theirs.
- Saving: `il_plugin_options` (`install-lib.sh:434-446`) writes every answer setup was given this run over the
  key's current value; a key setup was not given is left as it is. The "beats this answer" note goes. The machine
  manifest still records only keys that had no value before, so uninstall removes only what setup added.
- Setup questions (`skills/setup/SKILL.md`, saved answer first when there is one, recommended first otherwise;
  each answer becomes `--option` lines): "Main": Opus, default effort (recommended) | Opus high | Opus medium.
  "Builder model"/"Builder effort": as today (~110-117). "Fixer", next to them: Same as Builder, then Opus high
  (recommended: writes nothing) | Opus high every round (`fixerFirstModel=opus`, `fixerFirstEffort=high`) |
  Builder's model every round (`fixerEnabled=false`). "Reviewer" (~64, the profile question, kept): Codex |
  Claude. "Reviewer model": Sol medium (recommended) | Astra high | Sonnet high (Claude) (filtered by the agent).
  "Plan author": Opus high (recommended) | Sonnet medium | Off. "Sol judge" and "Astra judge": Codex high
  (recommended) | Claude Sonnet high | Off. "Fast tier" (multi-select, kept from ~133): None (recommended) |
  Plan author | Judges | Reviewer. A typed free-text answer takes any valid value. Setup refuses an OFF answer
  for main, Builder and reviewer naming the reason in the table, and asks again.
- `.claude-plugin/plugin.json` `userConfig`: 25 new keys (11 -> 36), each with `"project"` in `options` and as
  `default`; Claude model keys' options `opus|sonnet|fable`; Codex-capable model keys are free strings
  (a family or a `gpt-` id) validated by the reader; agent keys `codex|claude`; enabled and fast keys booleans
  with `"project"` read as unset. Values live in the user's `settings.json`, never the plugin folder, so a plugin
  update cannot overwrite them.
- `pp_option` gets arms for the new keys (`/config` else routing) so `doctor.sh` prints one line per key.
- Catches: plan-tier's OFF branch (an owner who turned a seat off still gets it planned); `seat.sh`'s OFF refusal
  (a hand launch of an OFF seat); the validated reader (a hand-edited bad value on a silent fallback); the
  `claude` overlay's `Write` check (a Claude reviewer or judge that can write).
- Tests:
  - `scripts/__tests__/plugin-option.test.sh`: "a Claude role set in /plugin resolves to it and launches on it
    (planAuthorModel=sonnet; builderModel=sonnet)", "a Codex role set in /plugin resolves to it
    (codexReviewerModel=astra)", "an invalid model or effort is refused naming the role", "an unset key keeps
    routing's default", "a replaced routing file (a plugin update) keeps the /plugin value".
  - `scripts/__tests__/builder-codex-pass.test.sh` (its preflight/argv cases): "codexReviewerModel=astra beats an
    old project codexModels pin for codex-reviewer: the launched reviewer argv names the astra id", and
    "codexReviewerAgent=claude: the pass runs headless Claude on sonnet and its argv denies Write, Edit and
    NotebookEdit"; "codexReviewerAgent=codex (unset): the pass runs the companion on sol".
  - `seat-launch.test.sh`: for each judge, "agent codex launches the read-only Codex sandbox" and "agent claude
    launches Claude sonnet with Write, Edit, NotebookEdit denied (the record says readonly)"; "two Claude judges
    are two seats with two records".
  - `seat-run-refused.test.sh`: "planAuthorEnabled=false, planJudgeSolEnabled=false, planJudgeAstraEnabled=false:
    `seat.sh launch <role> <unit> <spec>` is REFUSED naming the key and opens no pane and writes no record".
  - `plan-tier.test.sh`: author off -> No plan; sol off -> Plan + judge on astra; both off -> One planner; Panel =
    author, astra, sol.
  - `install-lib.test.sh`: "a rerun that changes an existing value writes it (fixerEnabled=false, then setup
    answers Opus high every round: fixerEnabled becomes true and fixerFirstModel=opus is saved)" and "a key
    setup was not given keeps its value".
  - setup cases (`install-lib.test.sh`; `requirements.test.sh` holds the `--profile claude` cases): "`--profile claude` writes the three
    Agent keys as claude", "`--option codexReviewerEnabled=false` (and the orchestrator and builder ones) is
    refused naming why", "a saved `codexModels`/`planFast`/`codexFast` moves into its key on rerun".
  - `scripts/__tests__/plugin.test.sh` ~41-62: count 36, the fixer option's default matches setup's recommended
    answer (~50-51 table gets the fixer row). `doctor.test.sh` ~209 is count-driven: run it.

## 5. the host project twin

The twin `role-cut-2026-10-22` builds the same fixer rule. It has not merged (no plan file for it found under
the host project repo's `.claude/plans/`), so issue 313 is built from the issue's text and the batch brief here. Once the
twin merges, its fixer commit is ported by commit (plugin builds port host fixes by commit); the evidence says so.

## 6. Established practice

- Dead-code removal with a callers map: followed (section 1, plus the `rg` evidence command).
- Plugin `userConfig` as the one user-facing settings surface: followed for agent, model, effort, fast tier and
  on/off; setup writes the keys and readers read only the keys (section 4).

## 7. Catches

Added steps carry their line: the subagent nudge (section 2), the fixer rule and its filename guard (section 3),
plan-tier's and seat.sh's OFF branches, the validated reader and the overlay's `Write` check (section 4). The role
deletions are pure deletions and add no flow step, so they carry none.

## 8. Version and CHANGELOG

Next free minor: 0.26.0 (now 0.25.3; `git log --all -S'"version": "0.26.0"'` finds nothing). Bump
`.claude-plugin/plugin.json` `version`; add `## 0.26.0 -- <date>` to `CHANGELOG.md`: the 8 roles and the three
agent files removed (helpers are the built-in Explore and general-purpose), Panel on three seats, the reviewer
and judges choose Codex or Claude (the Claude-only profile sets that), the fixer rule, every role's settings in
`/plugin` config with on/off where it has a meaning, and setup's old model flags folded into `--option`.

## Files

Edited: `config/routing.json`, `.claude-plugin/plugin.json`, `CHANGELOG.md`, `scripts/paths.sh`,
`scripts/plan-tier.sh`, `scripts/seat.sh`, `scripts/setup.sh`, `scripts/install-lib.sh`,
`scripts/builder-launch.sh`, `scripts/builder-codex-pass.sh`, `scripts/builder-fresh-round.sh`,
`scripts/codex-helpers.sh`, `scripts/worktree-setup.sh`, `scripts/doctor.sh`, `scripts/update.sh` (wording only
if it names a folded flag), `scripts/proof-run.sh` (same), `hooks/agent-model-guard.sh`, `skills/setup/SKILL.md`,
`templates/main-session.md`, `templates/_builder-brief-template.md`, `templates/AGENT_STARTUP.md`,
`templates/paved-road.md`, `docs/configuration.md`, `docs/hooks.md`, `docs/review-loop.md`,
`docs/first-build.md`, `docs/troubleshooting.md`, `docs/proof-run.md`, the dashboard producer if section 3's
check needs it; tests: `builder-fresh-round.test.sh`, `plugin-option.test.sh`, `builder-codex-pass.test.sh`,
`plan-tier.test.sh`, `plugin.test.sh`, `seat.test.sh`, `seat-run.test.sh`, `seat-run-refused.test.sh`,
`seat-fence.test.sh`, `seat-plan-marker.test.sh`, `seat-launch.test.sh`, `builder-launch-resume-rollback.test.sh`,
`to-main.test.sh`, `subagent-usage.test.sh`, `version-check.test.sh`, `install-lib.test.sh`,
`requirements.test.sh`, `fixtures/builder-launch-resume-setup.sh`, `hooks/__tests__/agent-model-guard.test.sh`,
`hooks/__tests__/builder-search-guard.test.sh`, `hooks/__tests__/dependency-addition-guard.test.sh`, and any test
that passes a folded setup flag (Builder: `rg -n -- '--(builder-model|builder-effort|codex-model|plan-models|plan-fast|codex-fast|no-codex-fast)' scripts skills docs`).
Deleted: `agents/` (helper.md, lean-worker.md, lean-checker.md), `scripts/platform-audit/` (6 files),
`scripts/__tests__/platform-audit.test.sh`, `scripts/builder-claude-pass.sh`; the `codex-headless` template if
Decision 12's check is empty.

## Done when

- The in-pane `/effort` check's command and result are in the evidence, and section 3 follows its branch.
- `jq '.roles|keys' config/routing.json` prints exactly the 7 kept keys, and `ls agents` fails (evidence file).
- The section 1 `rg` loop returns only CHANGELOG and `.claude/plans/` history hits (command and output in
  evidence), and `rg -n 'builder-claude-pass|## Design check|paved-road-areas'` plus the folded-flag `rg` above
  are empty outside that history.
- Each edited test file passes when run alone; the three issue 313 cases, the filename-guard cases, the guard cases and
  the issue 312 cases above exist and pass.
- `plugin.json` has 36 `userConfig` keys, version 0.26.0; CHANGELOG has the 0.26.0 entry.
- Evidence records that issue 313 was built from the issue text pending the twin's merge.
- No order or decision ids in this plan or the CHANGELOG entry (the leak test).

## Main answers

1. Every agent file the plugin ships is deleted, `helper.md` included; helpers are the built-in `Explore` (Haiku) and `general-purpose` (Sonnet).
2. Builders, Fixers and planners keep Haiku and Sonnet subagents: both guards point at the built-in types, with passing-call tests.
3. The Claude-only profile stays; the reviewer and both judges get a real Codex/Claude agent key with the read-only overlay, tested on both agents.
4. All seven roles get their keys (orchestrator included), and setup asks and saves them.
5. One settings surface: fixed accepted-value lists, explicit setup answers overwrite, setup-only flags fold into the keys, one precedence order.
6. OFF is refused where the seat launches; orchestrator, Builder and reviewer cannot be off and setup refuses it.
7. The fixer rule applies only to fix hand-offs (the filename guard stays).
8. Committed plans under `.claude/plans/` are history like CHANGELOG and stay untouched.
9. The Builder first checks `seat.sh effort` on an idle Claude pane; if it does not take, pass 2+ opens a fresh fixer seat at Opus high.
10. `--risky` stays, only as the three-reviewer trigger.

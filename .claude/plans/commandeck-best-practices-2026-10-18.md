# Plan: commandeck-best-practices-2026-10-18 -- Claude Code best practices in the plugin and the setup it configures

The owner's order (2026-10-18): bring the applicable Claude Code best practices into the plugin and into the
environment it sets up. Nine candidate items; this plan keeps seven parts and drops the rest with a reason.
Folded in: issue 169 (setup's fast-tier question has no "none"), issue 189 (fresh Builder phases, Compact
Instructions), issue 190 (lean helper agent with `omitClaudeMd`). Scope change (owner, 2026-10-18): every open
plugin issue, 169 to 190, is in this build. Items 8-26 take issues 170-188, one item each; each was checked
against the code at d154980 and still reproduces, so none is dropped.

Issue numbers are written "issue 169" here and in the build: `ci/leak-test.sh` refuses a hash and three digits
everywhere except CHANGELOG.md. No personal names, handles, ruling ids or user paths in anything shipped.

Sources read for this plan (code.claude.com/docs/en/...): best-practices, memory, skills, sub-agents,
auto-mode-config, sandboxing, plugins-reference, prompt-caching, costs, mcp. Facts used, each from those pages:
- memory: target under 200 lines per CLAUDE.md; MEMORY.md loads its first 200 lines or 25 KB, the rest is
  dropped; rules with `paths:` load only for matching files.
- skills: description + `when_to_use` is cut at 1,536 characters; SKILL.md under 500 lines;
  `disable-model-invocation: true` for side-effect workflows also takes the description out of context;
  `/skill-doctor` shows each skill's cost and use.
- sub-agents: `omitClaudeMd: true` starts a custom subagent without user/project/local CLAUDE.md (v2.1.271+);
  `maxTurns` is a frontmatter field; plugin subagents ignore `hooks`, `mcpServers`, `permissionMode`; a plugin
  agent's type is its scoped name (`<plugin>:<agent>`).
- best-practices / costs: CLAUDE.md can say what compaction must keep ("Compact instructions").
- auto-mode-config: the classifier ignores `autoMode` in `.claude/settings.json` and `.claude/settings.local.json`;
  a list without `"$defaults"` replaces the built-in list; the working repo and its remotes are trusted by default;
  `claude auto-mode config`, `claude auto-mode critique`, `claude auto-mode defaults`.
- sandboxing: in auto mode the server-side classifier still reviews sandboxed commands.
- mcp: tool search is on by default; off with `ENABLE_TOOL_SEARCH=false` or `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`,
  and, while `ENABLE_TOOL_SEARCH` is unset, when `ANTHROPIC_BASE_URL` is a non-first-party host (`true` overrides that).
- plugins-reference: `claude plugin validate <dir>` is the authoritative manifest and component check.

Fitting skill (mattpocock-skills is installed): `mattpocock-skills:tdd` for items 5 and 6 (new branches in
`install-lib.sh` and `instruction-lint.py`): red first, then green.

## Items

### 1. Instruction size guard and Compact Instructions (candidates 1 and 3; issue 189)

Confirmed today: every instruction template is under 200 lines (`AGENT_STARTUP.md` 80, `main-session.md` 170,
`global-claude.md` 114, `global-rules.md` 48), and `main-session.md` already keeps its detail below
"## Details (not injected)" ~85. Nothing needs moving; the part that is missing is a guard, and the compaction steer.

- `scripts/__tests__/plugin.test.sh` (after the manifest checks, ~40): one check that each of those four templates
  is at most 200 lines, with the reason in the check's name (a longer file loads in every session and is followed
  less well). `startup-size.sh` stays as it is: it holds the hooks' printed bytes (10,240 per hook), and
  `global-claude.md` / `global-rules.md` never pass through a hook, so a line limit there would miss them.
  Item 6 holds the project's own installed copies.
- `templates/AGENT_STARTUP.md` (new section after "## Rules for every pane", ~81): `## Compact instructions`,
  about 6 lines: when compacting, keep the role and unit, the brief and evidence file paths, the current commit,
  each open review finding by id, the test commands with their last result, the files changed, and every pane
  handle, task id and dispatch id given; drop file contents and tool output already acted on. This file loads
  into every pane through `agent-startup-context.sh`, and the SessionStart entry in `hooks/hooks.json` has no
  matcher, so it is printed again after a compaction.
- Fresh session per Builder phase: already shipped, no change. A Builder past its clear line (default 180K,
  `hooks/lib/project.sh` ~60) writes a hand-off and `builder-fresh-round.sh` goes on in a fresh session of the
  same pane (`hooks/context-line.sh` ~19-28); each NO-GO round and `builder-add-work.sh` start fresh too.
  Issue 189 closes with this item.
- Pre-existing fix: `templates/main-session.md` names `compact-gate.sh` at ~78, ~153-154 and ~169-170. The plugin
  never shipped that hook (`git log -S compact-gate -- hooks` finds nothing), so main is told to wait for a
  message that never comes. ~78: drop the clause "`compact-gate.sh` says \"compaction held\","; ~153-154: drop the
  sentence "`compact-gate.sh` auto-compact is 500K (`.claude/settings.local.json`)."; ~169-170: delete the
  "After three holds..." bullet.

Red first: the new plugin.test.sh check fails on a scratch copy of `AGENT_STARTUP.md` padded to 201 lines
(`red-proof.sh`). Size: ~20 changed lines. Ponytail: rung 2 (existing test file, existing hook); lazier option
rejected: putting the size check in `startup-size.sh`, which measures hook bytes and never sees the global files.

### 2. Skills (candidate 2)

Confirmed: setup, update, uninstall and handoff set `disable-model-invocation: true`. Descriptions are 164-330
characters, none has `when_to_use`, and the longest SKILL.md is 244 lines (setup).

- `skills/worktreereview/SKILL.md` frontmatter ~2-4: add `disable-model-invocation: true`. It launches a
  background `claude -p` writer session (~183-185) and opens an Orca tab: it spends money and changes the owner's
  screen, and its 330-character description loads into every pane today, Builders and helpers included.
- `skills/doctor` stays model-invocable: `doctor.sh` changes nothing (its header), and its use is Claude reaching
  for it when the wiring fails.
- `scripts/__tests__/plugin.test.sh`: one check per skill: SKILL.md at most 500 lines; description plus
  `when_to_use` at most 1,536 characters; and setup, update, uninstall, handoff and worktreereview carry
  `disable-model-invocation: true` (a side-effect skill Claude could start by itself is the failure this guards).

Red first: the dmi check fails before the frontmatter line is added. Size: ~12 lines. Ponytail: rung 5 (one
frontmatter line); lazier option rejected: no test, which lets the next side-effect skill ship without the flag.

### 3. Lean helper agent (candidate 4; issue 190)

The plugin ships no agents today. Builders run helper waves (`templates/_builder-brief-template.md` ~20-25) and
main runs helpers (`main-session.md` ~62-63, ~118-122); each non-Explore helper loads CLAUDE.md and git status.

- New `agents/helper.md` (plugin root; Claude Code scans `agents/` without a manifest entry):
  frontmatter `name: helper`, a description ("a fact-gathering helper whose prompt carries everything it needs;
  runs scripts and counts; changes nothing"), `tools: Read, Grep, Glob, Bash`, `omitClaudeMd: true`,
  `maxTurns: 40`. No `hooks`, `mcpServers` or `permissionMode` (ignored for plugin agents) and no `model`.
  Body, the rules a helper needs since no CLAUDE.md loads (~10 lines): the prompt is the whole brief; compute,
  do not read (python3, rg, jq; answer with output and source paths); output over 40 lines goes to a file under
  the scratch folder the prompt names; answer in at most 15 lines; say what is unanswered; change nothing (no
  edits, commits, stash, push, or messages to other panes). `maxTurns: 40` turns main-session's "stopped by 40
  turns" rule into a limit Claude Code enforces.
- `hooks/agent-model-guard.sh` ~22: add `"commandeck:helper": "sonnet"` to the map. Without it an unnamed helper
  call is rewritten to Opus, the costliest seat. One agent type, like the Explore and general-purpose entries:
  not a blanket subagent model.
- `templates/_builder-brief-template.md` ~22: one line: a helper that runs commands or counts (not a code search,
  which stays Explore) is `commandeck:helper`; it starts without CLAUDE.md, so its prompt carries every fact and
  limit it needs.
- `templates/main-session.md` ~62: name `commandeck:helper` in the "Helper agents compute" bullet (a few words).
- `ci/version-check.sh` ~15: add `agents/` to `PLUGIN`, so a change to the agent moves the version.

Red first: `hooks/__tests__/agent-model-guard.test.sh` +1 check (an unnamed `commandeck:helper` call runs as
sonnet; red before the map entry); `plugin.test.sh` +1 check that `agents/helper.md` sets `omitClaudeMd: true`
and `maxTurns`, and carries none of the three keys plugin agents ignore (each would be a silent no-op).
Size: ~40 lines. Ponytail: rung 3 (a platform feature: agent frontmatter); lazier option rejected: frontmatter
`model: sonnet` alone, which the guard's `updatedInput` overrides with Opus.

### 4. CI: plugin validate, and the version check before merge (candidate 5)

- `.github/workflows/ci.yml`, a step after "Leak test": install a pinned Claude Code CLI with npm
  (`npm install -g @anthropic-ai/claude-code@<version>`, the version the Builder ran it with locally) and run
  `claude plugin validate .`. CI runs no validate today. The Builder runs `claude plugin validate .` locally
  first, with the new `agents/` folder in place.
- The 0.13.2 lesson: the Builder raised only CHANGELOG.md, not `plugin.json` and the README badge, and CI's
  version check failed on the first push. This repo's own `.claude/commandeck.json` `testCommand` becomes
  `bash ci/version-check.sh main && bash scripts/run-shell-tests.sh --changed`. `merge-unit-local.sh` ~252 runs
  it on a copy of the squashed tree, where `main` resolves and version-check counts uncommitted files against
  the merge base, so a plugin branch without a version bump is refused at merge, not at push. This is the
  repo's config, not plugin code (`.claude/` is outside `PLUGIN` in version-check.sh).

Red first: `scripts/__tests__/version-check.test.sh` +1 case: a change under `agents/` with no version move
exits 1 (red until item 3's `PLUGIN` line). The CI step is checked by its run. Size: ~8 lines. Ponytail: rung 2
(existing script, existing check hook); lazier option rejected: a line in the Builder brief, which a Builder can
skip; the merge check cannot be skipped.

### 5. Auto mode: entries in user settings, and doctor pointers (candidate 6)

Confirmed: setup writes no `autoMode` today. Plugin worktrees run in auto mode (`worktree-setup.sh` ~131 sets
`defaultMode: "auto"`), so a false refusal stalls a Builder.

- `scripts/install-lib.sh`, beside `il_cache_ttl` ~183: `il_auto_mode <manifest> <settings file> [off]`, same
  shape (a value the owner set stays theirs; off takes out only what setup wrote). Two prose entries, built at
  setup time (nothing personal in the shipped text):
  1. "Trusted repo: <homepage from the installed plugin.json> (the Commandeck workflow plugin). Its scripts and
     hooks under <plugin folder> are this workflow's own tools, run by every pane."
  2. "Key internal services: Orca panes on this machine. The relay pane (the worktree ending in
     /Chief-of-Staff) passes the owner's answers to main word for word; main checks each against the owner's
     ruling log before acting."
  Writes: no `autoMode.environment` -> `["$defaults", 1, 2]`; a list with `"$defaults"` -> entries appended once
  (a re-run adds nothing); a list without `"$defaults"` -> nothing written, and setup prints that the owner's list
  replaces the built-in one and how to keep it (add `"$defaults"`). The entries setup added are recorded in the
  machine manifest (`$IL_MACHINE`), since `~/.claude/settings.json` serves every project.
- `scripts/setup.sh`: flag `--auto-mode add|leave|remove` (TAKES ~50, parse beside `--cache-ttl` ~201, saved answer
  beside `CACHE=$(old .cacheTtl)` ~108, config write ~355, call near `il_cache_ttl` ~381 with
  `$HOME/.claude/settings.json`). `leave` changes nothing at all: no write and no removal, whatever an earlier setup
  or another project wrote (J2: the entries are machine-wide, `$IL_MACHINE` is shared by every project,
  `install-lib.sh` ~19, so a removal on Leave would take entries another project uses). `remove` is the one answer
  that takes setup's recorded entries out, and only on the owner's explicit pick. Unlike `--cache-ttl default`,
  which is per project, Leave is not a removal.
  The Builder checks that `update.sh` replays the saved answer as it does the cache answer.
- `scripts/uninstall.sh` ~67, the machine block: `il_auto_mode "$IL_MACHINE" "$S" off`. The Builder confirms that
  block runs only once no project is left set up; if it runs per project, the call is gated on that, so one
  project's uninstall never takes another's entries.
- `skills/setup/SKILL.md`, a question after "Prompt cache" (~158-160): `Ask "Auto mode": Add two entries
  (recommended) | Leave as is | Take them out`. Add: "Your Claude panes run in auto mode. Two plain-English lines go
  into ~/.claude/settings.json, kept with Claude Code's built-in list, so its safety check knows the plugin's scripts
  and the relay pane. They apply in every project on this machine. `--auto-mode add`". Leave as is: "Changes
  nothing in ~/.claude/settings.json; a refusal of a plugin script stays possible. `--auto-mode leave`". Take them
  out (offered only when the machine manifest records entries setup wrote): "Removes the two lines setup added, for
  every project on this machine; your own entries stay. `--auto-mode remove`". README ~157: one table row.
  The project repo is not named: the classifier trusts the working repo and its remotes by default.
- `scripts/install-lib.sh`: `il_auto_mode_report`, called by `doctor.sh` the way `il_notify_report` is (~111):
  warn when any of `environment`, `allow`, `soft_deny`, `hard_deny` in `~/.claude/settings.json` lacks
  `"$defaults"` (it replaced the built-in list), and when a project `.claude/settings*.json` carries `autoMode`
  (the classifier ignores it there: move it to `~/.claude/settings.json`). Every line ends with where to look:
  `claude auto-mode config`, `claude auto-mode critique`, `/permissions` "Recently denied".

Red first, in `scripts/__tests__/install-lib.test.sh` on hand-written settings files: no list -> written with
`"$defaults"` first; a list with `"$defaults"` -> entries once after two runs; a list without it -> file unchanged
byte for byte; off -> only setup's entries go, an owner's entry stays; leave after an earlier add -> the settings
file and the machine manifest unchanged byte for byte (J2's case: a second project answering Leave keeps the first
project's entries). In `doctor.test.sh`: a list without `"$defaults"` -> the warn line; a project file with
`autoMode` -> the move line. Size: ~100 lines.
Ponytail: rung 2 (`il_cache_ttl`'s pattern, the doctor's report pattern); lazier option rejected: the doctor
pointers alone, which leave the documented fix for false refusals to every owner by hand.

### 6. Doctor checks (candidate 7)

- `scripts/instruction-lint.py` (the doctor already turns its rows into one warn line with the command, ~40):
  two kinds, docstring updated:
  - `over-200-lines`: the project's CLAUDE.md, each `.claude/rules/*.md` with no `paths:` frontmatter, and the
    global CLAUDE.md, each over 200 lines. AGENT_STARTUP.md and main-session.md are left out: a hook prints
    them, and `startup-size.sh` already holds them to 10,240 bytes.
  - `memory-over-limit`: MEMORY.md over 200 lines or 25 KB (25,600 bytes): what is past that is not loaded.
- `scripts/install-lib.sh`: `il_tool_search_report`, printed by `doctor.sh` after the add-on servers (~95):
  works out the effective setting first (J5; docs, mcp "Configure tool search"), each variable read from the
  environment, else `env` in the project's local, project and user settings, in that order:
  `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` set -> off; `ENABLE_TOOL_SEARCH=false` -> off; `ENABLE_TOOL_SEARCH`
  `true` or `auto[:N]` -> on; unset -> off only when `ANTHROPIC_BASE_URL` names a host other than
  `api.anthropic.com` (the docs' non-first-party fallback), else on. Off warns "tool search is off (<the reason>),
  so every tool of N MCP servers loads on every turn"; on is ok with N. The fallbacks by model and by cloud
  provider are not judged: the doctor does not know the session's model. N counts `mcpServers` in
  `~/.claude.json` (global and this project's) and `.mcp.json`, read as doctor.sh ~92 already reads them.
- `scripts/doctor.sh`: one ok line: "skills: N plugins enabled; each model-invocable skill's description loads
  in every session; run /skill-doctor to see each one's cost and use". N from `enabledPlugins` in
  `~/.claude/settings.json`. A pointer only: turning skills off is the owner's call.

Red first, `scripts/__tests__/doctor.test.sh` on a hand-written repo: CLAUDE.md of 201 lines flagged, 200 not; a
300-line rules file with `paths:` not flagged, without it flagged; MEMORY.md of 201 lines flagged, 10 lines of
26 KB flagged. Tool search, one case per row of the rule: `ENABLE_TOOL_SEARCH=false` -> warn; a proxy
`ANTHROPIC_BASE_URL` with the variable unset -> warn; the same proxy with `ENABLE_TOOL_SEARCH=true` -> ok;
`ANTHROPIC_BASE_URL=https://api.anthropic.com` unset -> ok; `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` with
`ENABLE_TOOL_SEARCH=true` -> warn. Size: ~62 lines. Ponytail: rung 2 (instruction-lint
and the report pattern); lazier option rejected: a new doctor script, a second home for the same reads.

### 7. Setup's fast-tier question gets "None" (candidate 8 shape; issue 169)

- `skills/setup/SKILL.md` ~130-131: options become `None (recommended) | Planners | Codex judges | Claude judge`,
  None first. None -> `--plan-fast ''`. None picked with a seat -> that seat alone. Four options is within the
  skill's rule (~17: up to four while the decoy is off). `setup.sh` already accepts `''`.

Test: none new; the change is skill prose and `--plan-fast ''` is existing behavior. The Builder confirms with
`rg -n "plan-fast" scripts/__tests__` that some test covers `''`, and adds one check where `setup.sh` flags are
tested if none does. Size: ~4 lines. Ponytail: rung 5.

### 8. Issue 170: setup and update offer to rebase an out-of-date relay worktree

Confirmed: neither `setup.sh` (relay at `$PP_WORKSPACES/Chief-of-Staff`, ~485) nor `update.sh` checks the relay
branch against main.
- New `scripts/relay-sync.sh [--rebase]` (~35 lines), the one check both skills call. With no flag: prints
  `relay: current`, `relay: none`, or `relay: <n> commits behind main` (`git rev-list --count <relay>..main`).
  `--rebase`: refuses with a plain line and changes nothing when the relay worktree has uncommitted changes;
  else `git -C <relay> rebase main`, and on a conflict `git rebase --abort` and a plain refusal. The base is the
  project's local `main`, not a fetched remote: the plugin merges locally and never pushes (AGENT_STARTUP, Rules),
  so local main is where the relay's hooks and rules come from. A fetch would compare with an older tip.
- `skills/setup/SKILL.md` (step "0. Check first" ~32, or with the relay question ~132) and `skills/update/SKILL.md`:
  run the check; when behind, `Ask "Relay": Rebase it (recommended) | Leave as is`, saying how many commits; only
  Rebase runs `--rebase`. Never without that yes.
- Test, new `scripts/__tests__/relay-sync.test.sh` (no existing test covers the relay worktree; a new script gets its
  own self-test, as every script here does): a scratch repo with a relay worktree 2 commits behind -> "2 commits
  behind"; `--rebase` -> current; a dirty relay -> refused, HEAD unchanged; a conflicting commit -> aborted, HEAD
  unchanged, no rebase in progress. Red: the script does not exist. Size: ~82 lines. Ponytail: rung 6 (no helper
  does this); lazier option rejected: skill prose with raw git commands, which leaves the dirty and conflict
  refusals to the model each time.

### 9. Issue 171: Codex limit alerts follow Codex's billing mode

Confirmed: `scripts/dashboard_alerts.jq` ~35 and ~74 gate the Codex alert and its missing-input line on
`.billing`. Change both to `.codexBilling != "api"` (set by `dashboard_limit.py` ~845).
Red first, `scripts/__tests__/dashboard-billing.test.sh` +2 cases: `{billing: "api", codexBilling: "subscription",
codex: {usedPct: 95, goalPct: 50}}` raises `limit-codex`; Claude on subscription and Codex on API raises none.
Size: ~12 lines. Ponytail: rung 5.

### 10. Issue 172: the dashboard's network-name choice sets the bind address

Confirmed: `skills/setup/SKILL.md` ~139-143 passes only `--hosts`; `setup.sh` keeps the saved bind (~118, ~401).
- SKILL.md: "On, this machine only" -> `--dashboard --bind 127.0.0.1 --hosts ''`; "On plus another name" ->
  `--dashboard --bind <network bind> --hosts <name>`, the network form `--bind` takes at `setup.sh` ~170 (the
  Builder reads it there; `0.0.0.0` unless setup names another). README's dashboard row says which choice listens
  on the network.
Test: none new; skill prose, and `--bind` is existing behavior. Size: ~4 lines. Ponytail: rung 5.

### 11. Issue 173: turning the dashboard off stops collecting the home project

Confirmed: `scripts/dashboard.sh` `projects()` ~830 collects the home project before reading the registry;
`setup.sh` ~404-407 Off unregisters and leaves the job.
- `dashboard.sh` ~830: collect the home project only while `registered` (~820) lists it, or the registry file
  does not exist yet (a job installed before any registration keeps today's behavior).
- `setup.sh` ~406: after the unregister, when `dashboard.sh`'s registry lists no project, run
  `dashboard.sh --uninstall` (~1019): no project, no job.
Red first, `scripts/__tests__/dashboard-built.test.sh` (it already builds a registry): an existing, empty registry
-> the home project is not in `projects.jsonl`. Size: ~22 lines. Ponytail: rung 2.

### 12. Issue 174: setup and update keep `generatedFiles`

Confirmed: the config rebuild at `setup.sh` ~349-367 writes no `generatedFiles`; `merge-unit-local.sh` ~112
reads it; update reruns setup (~62).
- `setup.sh` ~349: `--argjson gen "$(jq -c '.generatedFiles // null' "$IL_CONFIG" 2>/dev/null || echo null)"` and
  `+ (if $gen == null then {} else {generatedFiles: $gen} end)`. An empty output counts as null.
Red first: setup.sh cannot be run whole in a test, so `scripts/__tests__/plugin.test.sh` gets a contract check:
every key `merge-unit-local.sh` reads from `.claude/commandeck.json` (`generatedFiles`, `testCommand`) is named in
setup.sh's config writer. Red today on `generatedFiles`. Size: ~13 lines. Ponytail: rung 5; lazier option
rejected: no test, which lets the next owner key drop the same way.

### 13. Issue 175: Auto plan tier reads panel triggers in headings

Confirmed: `scripts/plan-tier.sh` ~21: a heading line ends in `next` before the panel match.
- In the heading branch, while `on` and the heading is deeper than the section's level, run the same panel
  match before `next` (move the panel loop into a function both branches call, or repeat the one loop).
Red first, new `scripts/__tests__/plan-tier.test.sh` (no test covers plan-tier.sh): a brief with `## The batch`
and `### Authentication` -> Panel; the same brief with a plain sub-heading -> not Panel; "The batch" heading words
themselves pick nothing. Size: ~27 lines. Ponytail: rung 5.

### 14. Issue 176: planning instructions offer each seat its own default model

Confirmed: `templates/main-session.md` ~30 and `templates/AGENT_STARTUP.md` ~27-28 say "default Opus high" for
every seat; `pp_plan_seat` (`paths.sh` ~585) already gives each seat its own allowed model, and `plan-tier.sh`
prints it.
- Both lines: offer, per seat, the models setup allows for that seat's agent, the default being the model
  `plan-tier.sh` prints for that seat, at high effort. ~4 lines.
Test: none; template prose. `startup-size.sh` re-run (item 1). Ponytail: rung 5.

### 15. Issue 177: the pane budget hook counts turns only when over budget

Confirmed: `hooks/lib/pane-budget.sh` ~52 runs grep, jq and sort over the whole transcript on every Edit, Write
and Bash; `COUNT` is used only in `PB_SUMMARY`, and `PB_SUMMARY` only in `pane-budget-gate.sh` ~90 after a fail.
- Compute the limit test first; return 0 when within budget; compute `COUNT` and `PB_SUMMARY` only on the fail
  path. ~6 lines.
Red first, `hooks/__tests__/pane-budget-gate.test.sh` +1 case: a within-budget call with a `sort` shim on PATH that
leaves a marker -> no marker; the over-budget message still names `turns=`. Size: ~16 lines. Ponytail: rung 5.

### 16. Issue 178: a branch diff over the reviewer's input limit is not pasted

Confirmed: `scripts/builder-codex-pass.sh` ~900-903 shrinks the diff twice (`DIFF_MAX` 400,000, `DIFF_HARD`
900,000) and then pastes it whatever its size.
- After ~903: when `${#DIFF}` is still over `DIFF_HARD`, `DIFF` becomes `git diff --stat` plus `--name-only` for the
  range, and `NOTE` tells the reviewers to read `git -C <worktree> diff <range> -- <path>` file by file. Same range,
  same whole-branch review, same merge proof. ~6 lines. Both reviewer kinds share this prompt.
Red first, `scripts/__tests__/builder-codex-pass.test.sh` +1 case with `COMMANDECK_PASS_DIFF_HARD` set small: the
prompt holds the file list and the read instruction and none of the diff body. Size: ~21 lines. Ponytail: rung 5.

### 17. Issue 179: the typed Codex pointer carries the seat tag

Confirmed: `scripts/dispatch-task.sh` ~62 types only `Read <file> and follow it...`; the tag is in the spec
(`seat.sh` ~301 "Seat tag <tag>: ...") and `read-verdict.sh` `given_spec` ~213 searches user prompts only.
- `dispatch-task.sh` ~62: append the spec's own `Seat tag ...` sentence (first match in `$spec`) to the typed text.
Red first, `scripts/__tests__/seat.test.sh` ~170 (it already stubs the typed pointer): the typed text contains the
record's tag. Size: ~10 lines. Ponytail: rung 5.

### 18. Issue 180: a verdict is printed in one canonical form

Confirmed: `read-verdict.sh` ~426 accepts `VERDICT:[[:space:]]*WORD`; ~827 prints the line with only its ends
trimmed; `seat.sh` ~462 matches `"VERDICT: GO"*`.
- ~827: add `s/^VERDICT:[[:space:]]*/VERDICT: /` to the sed. One line; every reader keeps its one-space pattern.
Red first, `scripts/__tests__/read-verdict.test.sh` +2 cases: `VERDICT:  GO` and `VERDICT:GO` print `VERDICT: GO`.
Size: ~6 lines. Ponytail: rung 5.

### 19. Issue 181: the Builder's token ledger sums every session

Confirmed: `builder-fresh-round.sh` ~88 appends `session=<id>`; `merge-unit-local.sh` ~379 passes only the tag;
`seat-event.sh` ~70-76 sums the one session the tag resolves.
- `merge-unit-local.sh` ~379: also pass `SEAT_EVENT_SESSIONS` = the record's `session=` ids.
- `seat-event.sh` ~76: for each id not already the resolved session, its log under the worktree's Claude
  projects folder, `seat_usage` summed into `USAGE` (token fields added; a missing log is named in `REASON`). ~12 lines.
Red first, `scripts/__tests__/merge-unit-local.test.sh` (its ledger-row case): a record with two `session=` lines
and two logs -> the row's tokens are the sum. Size: ~28 lines. Ponytail: rung 5.

### 20-24. worktreereview (issues 182-186), with item 2's flag

- 182: `skills/worktreereview/scripts/collect.py` `main_archive` ~433: read
  `~/.commandeck/briefs/<project>/<unit>.tar`, where `merge-unit-local.sh` ~329 writes it (`<project>` as
  `PP_PROJECT` names it; the Builder reads `paths.sh` for the exact form). Docstring updated. ~3 lines.
- 183: `collect.py` `round_threads` ~461 also reads `^Claude session: (id)$` headers (written by
  `builder-codex-pass.sh` ~513 for the Claude reviewer). One accounting home (J3): the Claude reviewer runs in the
  Builder worktree (`builder-codex-pass.sh` ~982), so its log is already in `sessions` (~582) and its tokens and
  cost are already counted once, at its own Claude prices, by the sessions loop (~649). That stays the only place
  its usage is counted. ~583-590 adds, for each such session, a pass entry with its start, end, round, kind and
  verdict (from the matching session in `sessions`) and empty usage: `usage: {}`, `rows: []`, `calls: 0`, so the
  runs loop (~691) adds nothing for it. The pass then numbers rounds and splits the review and fixing stages as a
  Codex pass does. ~25 lines.
- 184: `review.py` `places` ~38: take `--main` (parsed in `main()`, still passed through to collect.py), derive the
  project from it when given, and exit with a plain refusal when no project resolves instead of falling back to
  `project`. ~8 lines.
- 185: `collect.py` ~567: the default `--out` becomes `/tmp/commandeck/worktreereview/<project>/<unit>`, the folder
  SKILL.md ~45 reads and `review.py` uses. One home for the path; the skill's command needs no change. ~2 lines.
- 186: `review.py` `rungs` ~57: match `^\s*(\d+)\. (?:\[rung \d+\] )?(#\d+)`, the batch template's `1. #<n>: <title>`
  as well as the old form. ~1 line.
Red first, `scripts/__tests__/worktreereview.test.sh`, one case each: an archive at the merge script's path is
found (182); a fixture with a Builder log, a Claude reviewer log and a round file headed `Claude session:` gives a
review pass with its round and verdict, and the page's token and cost totals equal the two logs counted once, the
same totals as before the change (183, red today on the pass, and guarding J3's double count); a removed worktree
with `--main` files under that project, and without one is refused (184); collect without `--out` writes under
`<project>/<unit>` (185); `1. #12: Fix the hook` plus an evidence line gives a row with its rung (186).
Size: ~95 lines (182: 11, 183: 55, 184: 16, 185: 6, 186: 7). Ponytail: rung 5 each; lazier option rejected for 185:
passing `--out` in the skill (the issue's fix), which leaves collect.py's own default wrong for any other caller.

### 25. Issue 187: dashboard review time keeps a retried pass

Confirmed: `scripts/dashboard_builders.jq` ~100 pairs each `codex-start` with the first end of that pass and round.
- ~100: `reviewSec` is computed from `$cx` (~49), the pairing by log position the open-pass check already uses: each
  start with the first matching end that follows it in the log, an open one up to `$now`. A timestamp pairing is
  not used (J4): a retry that starts in the same second the failed try ended would pair with that old end. ~3 lines.
Red first, `scripts/__tests__/dashboard-built.test.sh` +1 case, J4's exact log: round 2 start 12:00:00, end
12:01:00, start 12:01:00, end 12:06:00 -> `reviewSec` 360 (60 today). Size: ~10 lines. Ponytail: rung 2 (reuses `$cx`).

### 26. Issue 188: an answer goes to the planner it names

Confirmed: `scripts/answer-worker.sh` ~64 picks the newest log of the pane's kind in the worktree; two Claude
planners share `<unit>-plan`.
- `answer-worker.sh` ~64: when a seat record (`$PP_SCRATCH/seat-*.txt`) has `handle=$H`, `log_state` calls
  `read-verdict.sh --state --worktree <wt> --agent <kind> --launched <record's launched=> --spec <record's tag=>`
  in place of `--current`: the launch binding (`read-verdict.sh` ~279-285) takes the first session after the
  launch that was handed that seat's spec, as `seat-event.sh` ~70 binds a seat. Adding `--spec` to `--current` would
  do nothing (J1): the `--current` branch (~267-277) picks the newest log and never reads the spec. No record, or
  no `launched=`, keeps today's `--current` lookup. ~6 lines.
Red first, `scripts/__tests__/answer-worker.test.sh` +1 case, J1's scenario: two planner seat records in one
`<unit>-plan` worktree, planner A's log waiting and planner B's log complete and newer; answering A reads A's log
and the answer goes to A's inbox, not typed. Red today (it reads B's). Size: ~30 lines. Ponytail: rung 2 (the
launch binding read-verdict already has).

### Release

`plugin.json` version, README badge, and a CHANGELOG entry naming issues 169 to 190 (plugin.test.sh holds all
three in step). ~25 lines.

Build order (the total stays under 1,000 lines, so one pass; grouped so each file is opened once): items 17-19
and 26 (seat hand-offs), 20-24 and 2 (worktreereview), 9, 11 and 25 (dashboard), 7, 8, 10, 12 and 5 (setup and
update), 13-14 and 1 (planning text and templates), 15-16 (hook and pass), 3-4 and 6 (agent, CI, doctor), release.

## Tests

Existing files are extended; two new test files, each for a script no test covers today: `relay-sync.test.sh`
(item 8, a new script) and `plan-tier.test.sh` (item 13). No install, uninstall or whole-setup run (owner ruling
2026-10-16).
- `scripts/__tests__/plugin.test.sh`: template line limit (item 1); skill limits and side-effect flags (item 2);
  helper agent frontmatter (item 3); the config keys setup must keep (item 12).
- `dashboard-billing.test.sh` (9), `dashboard-built.test.sh` (11, 25), `pane-budget-gate.test.sh` (15),
  `builder-codex-pass.test.sh` (16), `seat.test.sh` (17), `read-verdict.test.sh` (18),
  `merge-unit-local.test.sh` (19), `worktreereview.test.sh` (20-24), `answer-worker.test.sh` (26).
- Items 10 and 14 are prose only and carry no test; item 7 as stated there.
- `hooks/__tests__/agent-model-guard.test.sh`: unnamed `commandeck:helper` runs as sonnet (item 3).
- `scripts/__tests__/version-check.test.sh`: `agents/` counts as plugin (items 3, 4).
- `scripts/__tests__/install-lib.test.sh`: `il_auto_mode` add, re-run, owner's list without `"$defaults"`, off (5).
- `scripts/__tests__/doctor.test.sh`: auto-mode report, tool-search report, the two lint kinds (items 5, 6).
- After the build: `bash scripts/startup-size.sh` and `--per-prompt` (AGENT_STARTUP grows ~600 bytes),
  `claude plugin validate .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh main`.
Each red-first check is shown red with `red-proof.sh` on the line it guards.

## Dropped items

- Candidate 1, move workflow detail into skills or path-scoped rules: every template is under 200 lines and
  main-session's detail is already below its "not injected" line; nothing to move.
- Candidate 1, "always" rules into hooks: the main-session rules a hook can hold already are hooks (poll loops:
  `no-poll-loops.sh`; asks: `worker-ask-guard.sh`, `ask-records-decision.sh`; clear line: `context-clear-stop.sh`);
  the helper's 40-turn rule becomes `maxTurns` in item 3. No other cheap one found.
- Candidate 3, fresh Builder phases: shipped (Builder clear line and `builder-fresh-round.sh`, item 1).
- Candidate 6, the project repo as trusted: the classifier trusts the working repo and its remotes by default.
- Candidate 8, sandbox question: in auto mode the classifier still reviews sandboxed commands, so the refusals
  stay; and the plugin's hooks and scripts write outside the worktree (`~/.claude/checkpoints`, the scratch
  folder, Orca's socket, launchd jobs), so a default sandbox breaks them. Not worth a question.
- Candidate 8, prompt cache TTL: shipped (setup's "Prompt cache" question with "Leave default", `il_cache_ttl`).
- Candidate 8, auto-compact window: shipped where it matters (`worktree-setup.sh` ~78-83, ~126 writes
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` into each worktree's local settings); main restarts at its clear line first.
  A user-settings window would change every other project's sessions too.
- Candidate 9, `.claude/worktrees/` and `.worktreeinclude`: the plugin makes worktrees with Orca
  (`orca-ide worktree create`, then `worktree-setup.sh`), never `claude --worktree`; neither applies.
- Candidate 2, `disable-model-invocation` on doctor: read-only; Claude reaching for it is its use.
- Issues 169-190: none dropped. Each of 170-188 was checked at d154980 and still reproduces; 169, 189 and 190
  are items 7, 1 and 3.

## Not doing

- The declined items: built-in cross-session inbound messaging; a blanket subagent model.
- A remote fetch before the relay rebase (item 8): the plugin merges into local main and never pushes.
- Writing `skillOverrides` or turning plugins off: the doctor points to `/skill-doctor`; the choice is the owner's.
- `claude plugin validate --strict`; a plugin-level `settings.json`.
- Any install, uninstall or other end-to-end test.

## Risks

- `omitClaudeMd` needs Claude Code v2.1.271 or later. An older version ignores the field and the helper loads
  CLAUDE.md as helpers do today: no worse than now.
- Compact Instructions live in hook-printed text, not CLAUDE.md, which is what the docs name. The summarizer
  reads the whole context, and the hook prints the file again after a compaction, but how strongly it steers is
  unmeasured. The project's CLAUDE.md is the owner's file; the plugin does not write it.
- The CI validate step depends on npm and the CLI's validate needing no sign-in. If it needs one, the Builder
  drops the step and says so in the evidence file; the local run still stands.
- The version check in the merge check means a plugin branch must carry its own version bump (`plugin.json`,
  README badge, CHANGELOG) before merge, as plugin.test.sh already expects. A release bump made after the merge
  no longer works for this repo.
- The auto-mode entries are global to the machine. Entry 2 is a statement about trust; it is worded as fact plus
  the check main makes, the owner can decline it, and uninstall takes out only setup's entries.
- Item 8 rebases a worktree whose relay pane may be running: its hooks and rules change under the live session.
  The question says so; Leave as is is offered.
- Item 10's network choice makes the dashboard listen beyond this machine; names not on its list still get a 403.
  The owner picks it by name; the README row says so.
- Item 16 sends reviewers to read a huge diff themselves: more reviewer turns on such a branch, but a review
  instead of none.
- Item 21 keeps a Claude reviewer's tokens in the sessions totals (one home); on the page they sit in the review
  stage's Claude column, not in a column of their own. A separate reviewer column would need a render.py change.
- Item 26's launch binding finds a planner's first session after launch; a planner restarted in a new session
  later gets an unknown state from the log, and `idle()` (`answer-worker.sh` ~67) then goes by Orca's busy check
  alone (`pane_is_busy`), its existing second signal.
- Item 11 stops the shared job when the last project leaves the dashboard; a project re-enabling it reinstalls it.
- Seen, not in scope, to file as an issue: `worktree-setup.sh` ~57 and ~121-122 deny and allow names that belong to
  one project (`aws dynamodb ...`, `aws-cloudwatch-*`, `alphaxiv`) in a generic plugin.

Revision (judge J1-J5, all accepted after checking the code and the docs): J1 item 26 uses the launch binding,
not `--current`; J2 item 5's Leave changes nothing and removal is its own explicit answer; J3 item 21 keeps a
Claude reviewer's usage in the sessions totals only; J4 item 25 reuses the log-position pairing `$cx`; J5 item 6
works out the effective tool-search setting before warning.

Planned size: 49 files, ~660 changed lines (items 1: 20, 2: 12, 3: 40, 4: 8, 5: 100, 6: 62, 7: 4, 8: 82, 9: 12,
10: 4, 11: 22, 12: 13, 13: 27, 14: 4, 15: 16, 16: 21, 17: 10, 18: 6, 19: 28, 20-24: 95, 25: 10, 26: 30,
release: 25). Under the ~1,000-line aim, so no phase split; the build order above groups items by file.

Summary:
1. Covers all 22 open plugin issues (169-190): best-practice items 1-7 plus one item per issue 170-188, none dropped.
2. The best-practice part: size guards, Compact Instructions, a lean `commandeck:helper` agent, CI validate, a
   merge-time version check, auto-mode entries behind a question that keeps `"$defaults"`, doctor checks.
3. The bug part fixes each producer/consumer mismatch at one end, mostly a line or two, each with a red-first case.
4. Tests extend 14 existing files and add two (a new script, an untested script); nothing installs or uninstalls.
5. About 660 changed lines over 49 files; drops sandbox, cache TTL, compact window and worktree files with reasons.

PLAN-DONE

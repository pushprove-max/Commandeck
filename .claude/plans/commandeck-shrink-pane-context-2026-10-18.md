# commandeck-shrink-pane-context-2026-10-18 -- shrink the plugin's share of every worker pane's starting context

Plan judge: GO (round 2, after one revision). Part B of a two-repo plan; the per-role skill cuts the owner also
asked for (worker skill lists from the owner's per-install config) are a separate follow-up build after this one
merges, not part of this plan.

Public repo: no personal names, handles, pane names (other than the existing seat directory name
`Chief-of-Staff`) or user paths in any shipped file, comment, test or changelog line. Issue numbers are written
"issue 192" outside CHANGELOG.md.

## Who gets what

| Seat | Skill/plugin cuts (B1) | Auto memory (B2) | Ponytail (B3) |
|---|---|---|---|
| Main, main checkout | none | kept | full plugin |
| Chief-of-Staff relay | none (its existing slimming only) | kept | full plugin |
| Keep-all seat (`--keep all`) | none | kept | full plugin |
| Builder (`--builder`) | B1 cuts, minus the unit's keep list | off | ~1 KB summary, plugin off |
| Fixer and reviewer panes (in the Builder's worktree) | inherit the Builder worktree's file | off | summary |
| Planner, plan judge, other worker panes | B1 cuts, minus the keep list main gave | off | summary |
| Helper subagents | inherit their parent session | as parent | as parent |
| Codex seats | untouched (Codex loads no Claude skills or memory) | n/a | n/a |

## B1. Move 1 in `scripts/worktree-setup.sh`: worker seats drop Stripe and the browser skills

- **New `--keep <list>`, stored as `.env.COMMANDECK_SKILL_KEEP`.** Comma-separated words. Stored so a rerun
  without the flag keeps it; a rerun that passes `--keep` replaces the stored list (the same pattern as the
  existing stored Builder flag). Today `${2}` is `--builder` or `--print-settings`, and both must keep working:
  parse `--builder` and `--keep` in any order after `<wt>`.
  - `billing` keeps the stripe plugin.
  - `all` makes a keep-all seat: a rerun deletes every leaf B1-B3 owns, and writes none.
- **Worker and Builder seats:**
  - `enabledPlugins.stripe@claude-plugins-official = false` unless `billing`.
  - `skillOverrides` `"off"` for `anthropic-skills:computer-use`, `anthropic-skills:built-in-browser`,
    `anthropic-skills:chrome-browser`.
  - Setting a false or off entry for something not installed is harmless.
- **Removal is exact.** A rerun deletes every leaf this script owns (one jq list of owned leaves) before writing
  the current set, so the keep list works both ways: adding `billing` later removes `stripe: false`. The script
  never deletes a leaf it does not own; an owner's hand-set `skillOverrides` entry survives.
- **The relay branch is unchanged.**
- **`scripts/builder-launch.sh`** passes `--keep`. `--print-settings` reads the stored keep (plan-worktree-close.sh
  compares the two).
- **Already shipped:** five of the plugin's six skills set `disable-model-invocation`. `doctor` stays
  model-invocable on purpose: main runs it when a wake-up is missed.
- **Description trims:** none needed. The plugin's one listed skill, `doctor`, has a 230-character description.
- **Red first, in `scripts/__tests__/worktree-setup.test.sh`** (extend): the worker file and the Builder file
  have the four leaves. `--keep billing` leaves the stripe key unset, and so does a rerun without the flag.
  `--keep all` on a seeded file removes them. The relay file has none. An owner's hand-set `skillOverrides`
  entry survives a rerun.

## B2. Move 2: workers skip MEMORY.md

- `worktree-setup.sh`, worker and Builder seats: `.autoMemoryEnabled = false` (a file key, not the env var, so it
  survives every relaunch path). Not on the relay, not with `--keep all`; a rerun on either deletes it. Main is
  never a worktree.
- **Risk: a worker misses a memory nobody briefed. Brief coverage:**
  - `templates/_builder-brief-template.md`, "How to work": "Auto memory is off in this pane. If the work hinges
    on a ruling or fact the brief does not state, ask main with the orchestration ask command before guessing."
  - `templates/main-session.md`, below its `## Details (not injected)` heading, next to the existing pointer line:
    "Worker panes run without auto memory. Copy into the brief every memory fact the unit depends on: the ruling
    with its id, configured values, known traps. A brief never cites a memory by file name alone." It goes below
    that heading because main's print is already near the size line.
  - `templates/AGENT_STARTUP.md`, "Rules for every pane", one line: "Worker panes run without auto memory; the
    brief carries what you need."
- **Doctor (issue 192, folded with the cache-TTL check).**
  - In a git worktree Claude Code applies the main checkout's `.claude/settings.local.json` over the worktree's
    own for the same key. `scripts/doctor.sh` warns for every leaf that `worktree-setup.sh --print-settings`
    writes and that the main checkout's `.claude/settings.local.json` also sets with a different value.
  - This generic check replaces the TTL-only check the cache-TTL build (0.15.0) added, if that check is a subset
    of it. If the TTL check carries extra advice for the relay, keep that advice as the generic check's message
    for the TTL key. One check, not two.
  - Issue 192 closes on this.
- **Red first:**
  - worktree-setup.test.sh: `autoMemoryEnabled` is false on worker and Builder seats, and absent on the relay and
    on `--keep all`.
  - `scripts/__tests__/doctor.test.sh`: a scratch main-checkout local file with `autoMemoryEnabled: true` makes
    the doctor warn and name `autoMemoryEnabled`. An unrelated leaf does not warn. The existing TTL warning
    case still passes.

## B3. Move 3: startup text

- **Ponytail summary.** Applies when the owner has the ponytail plugin on (setup's `.ponytail` is true and
  `enabledPlugins["ponytail@ponytail"]` is true in user settings).
  - Worker and Builder seats get `ponytail@ponytail: false` and a SessionStart hook. The hook prints the new
    `templates/ponytail/SUMMARY.md`, 1,200 bytes or less, by the hook's full path, the way `worktree-setup.sh`
    already registers the notify hook.
  - The relay and main keep the plugin. This honours the existing "ponytail runs in every seat" comment at
    `worktree-setup.sh:63-64`. Update that comment to say workers run it through the summary.
  - With a skill-only install, nothing changes: no hook, one listing line.
  - The two ponytail leaves are owned leaves (B1 removal rule) and are removed with `--keep all`.
- **No template text to move.** `templates/global-claude.md` "Main session only" is generic, and the filing rules
  live only in `templates/main-session.md`, which is main-only. The Builder confirms this with
  `python3 scripts/merge-rules.py ... --report` over `global-claude.md` against `AGENT_STARTUP.md` and
  `main-session.md`, and moves any paragraph it reports as "already in".
- **Red first:**
  - worktree-setup.test.sh: with ponytail on in a scratch `HOME`, worker and Builder files carry the hook and the
    plugin set to false. With ponytail off or skill-only, neither.
  - `scripts/__tests__/plugin.test.sh`: SUMMARY.md is 1,200 bytes or less.
  - `bash scripts/startup-size.sh` stays green for all four seats. CI runs it.
- **Docs and version:** README seat table, CHANGELOG entry and the next version, following
  `ci/version-check.sh`.

## Verification

1. **Probe that each override works, before writing tests that rely on it.** Run
   `claude -p --model claude-haiku-5-5 --settings <(bash scripts/worktree-setup.sh <wt> --print-settings) '<list each named skill present/absent>'`
   and again without `--settings` as the control. Report each name as hidden or as having no effect; drop a name
   with no effect.
2. `bash scripts/startup-size.sh`: all four seats under 10,240 bytes; worker and Builder seats down.
3. Every test file extended runs red before its item and green after; `bash scripts/run-shell-tests.sh`,
   `claude plugin validate .`, `bash ci/leak-test.sh` and `bash ci/version-check.sh main` pass on the final tree.

## Risks

- A worker misses a memory nobody briefed: covered by the three brief lines in B2.
- A main-checkout local key shadows a per-worktree key: the B2 doctor check names it.
- No install, uninstall or whole-setup run during the build (owner ruling 2026-10-16); tests use scratch `HOME`
  and scratch repos.

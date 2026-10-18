# commandeck-skill-cuts-2026-10-18 -- per-role skill and plugin cuts from the owner's per-install lists

Plan judge: GO (round 2, as Part C of the two-repo shrink-pane-context plan). Follow-up to
`commandeck-shrink-pane-context-2026-10-18` (merged 04866d5, 0.16.0), whose move-1 entries this build leaves as they are.

Public repo: no personal names, handles, pane names (other than the existing seat directory name `Chief-of-Staff`) or
user paths in any shipped file, comment, test or changelog line. Issue numbers are written "issue N" outside
CHANGELOG.md.

## The build

The owner asked for the same per-role skill cuts in the plugin, as a separate build.

- **Settings, in `.claude/commandeck.json`:**
  - `workerSkillsOff`: a list of skill names that worker and Builder seats write as `skillOverrides: "off"`.
  - `workerPluginsOff`: a list of `plugin@marketplace` keys, written as `false`.
  - `keeps`: an object from a keep word to the `{skills, plugins}` it brings back.
  - Setup asks once for the owner's lists. Update keeps the owner's lists.
- **Ship the mechanism, not skill names.** The plugin ships no skill name in any default list, bundled names
  included: not code-review, simplify, schedule or any other.
  - The only built-in names allowed are the plugin's own skills. Those are already hidden by frontmatter, and
    settings cannot hide plugin skills (see below).
  - With no owner input, setup writes no `workerSkillsOff` entry, no `workerPluginsOff` entry and no `keeps`
    entry beyond the existing `billing`.
- **What the owner adds.** Every skill name, and any keep word with its skills (for example a tooling keep), comes
  from the owner's per-install lists. None of it is shipped.
- **The plugin's own skills.** setup, update, uninstall, handoff and worktreereview are already hidden by
  `disable-model-invocation`. `doctor` stays: plugin skills cannot be turned off by settings, and main uses it.
- **One sentence in the README:** plugin skills cannot be turned off one at a time. Only a whole plugin can be.
- **The move-1 entries are not touched.** The stripe plugin and the three browser skills stay as 0.16.0 ships them.
  This build adds the owner's lists on top of them and does not fold them into any shipped default.
- **Red first:**
  - worktree-setup.test.sh: a `commandeck.json` with a list and a keep produces exactly those leaves. A rerun
    after the list shrinks removes the dropped leaves.
  - `install-lib.test.sh` or `setup` tests, whichever owns `commandeck.json` writes:
    - With no owner input, setup writes no `workerSkillsOff` entry. Fail the test if any skill name appears.
    - An owner's list survives update.

## Ponytail ladder

Rung: extend the existing `worktree-setup.sh` stored-flag and `commandeck.json` patterns that 0.16.0 already uses for
the move-1 cuts; no new file, dependency or config surface beyond the three keys the owner asked for. Lazier option
rejected: hard-coding the owner's names as shipped defaults (forbidden in a public plugin).

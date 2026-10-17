# Plan: commandeck-plan-wt-autoclose-2026-10-17 -- planning worktrees close themselves (plugin)
1. `scripts/plan-worktree-close.sh` (new, ~60 lines) `<unit> [--dry-run]`, used at Builder launch and by main on a
   rejected plan. No `$PP_WORKSPACES/<unit>-plan`: silent, exit 0. Takes seat.sh ~74's lock, reads the mark as seat.sh
   ~76 does; a mark not `<unit>` prints `left <wt>: not <unit>'s planning worktree`, exits 0, touches nothing.
   The check: five layers, each on its own. B = `git merge-base HEAD refs/heads/main`. "Matches" = same mode AND object
   id as main's `git ls-tree refs/heads/main -- <path>` entry, or absent from both (r2 P2-b: chmod +x keeps the id).
   Every `git diff` here has `--no-renames` (r6 P2, checked: without it a rename lists only its new path, hiding the deletion).
   (a) commits: each path of `git diff --no-renames --name-only -z B HEAD`, read with `git ls-tree HEAD -- <path>`;
   (b) index: each path of `git diff --cached --no-renames --name-only -z B` and `... -z HEAD` (r7 P1), read with `git ls-files -s -- <path>` (Sol P1-b,
   checked: a staged revision with its working copy restored to HEAD leaves `git diff B` empty, `--cached` lists it);
   (c) working tree (`git diff --no-renames --name-only -z B` and `... -z HEAD`, r7 P1) and (d) untracked (`git ls-files -z --others --exclude-standard`): mode
   120000 for a symlink (id: hash of its `readlink` text), 100755 when executable, else 100644 (id: `git hash-object <path>`);
   (e) ignored (Sol P1-a): `git ls-files -z --others --ignored --exclude-standard --directory`; any entry refuses.
   `setup_made <path>` is skipped in (d) and (e) (r2 P2-a: git lists setup's link as untracked under `node_modules/`) and is true only for:
   `{,web/,infra/}node_modules` that is a symlink whose `cd <it> && pwd -P` equals that of `$PP_MAIN/<path>` (r3 P2, checked: setup links
   `/repo//node_modules`); and `.claude/settings.local.json` whose bytes `cmp -s` equal `bash worktree-setup.sh <wt> --print-settings` (item 6; r3 P1:
   setup keeps custom keys like `env.LOCAL_NOTE`; r4 P1-a: read-only, it never links or writes in `<wt>`). Any mismatch, one line, exit 1:
   `REFUSED: <wt> holds <path> (<layer>), not identical on local main; left in place (bash <scripts>/plan-worktree-close.sh <unit> once it is)`.
   Order (r4 P1-b): check 1 -> `--dry-run` prints `would close <n> panes and remove <wt>` and stops -> close each pane by handle and `codex-helpers.sh stop
   <wt>` (STEP 5 ~393-398, minus its warn-and-continue at ~395, r5 P1) -> check 2 -> only then `orca-ide worktree remove --worktree path:<wt> --force`,
   printing `closed <unit>-plan`. A check-2 REFUSED line adds `(written while panes closed)`. A failed `terminal list`, a `terminal close` exiting
   non-zero, or a pane still listed for `<wt>` after the loop: no removal, exit 1, one line per pane: `kept: <wt>: pane <handle> did not close`.
2. `scripts/builder-launch.sh` ~141 `open_builder`: `exec bash seat.sh launch builder ...` becomes `bash seat.sh ... ||
   exit $?`, then `bash "$HERE/plan-worktree-close.sh" "$UNIT" >&2 || true` and `exit 0`. The close runs only after the
   Builder's pane opened, and a refusal never fails the launch. ~113 comment: the lock is held "until this script exits".
3. `scripts/builder-launch.sh` ~203 `--dry-run`, before `exit 0`: `bash "$HERE/plan-worktree-close.sh" "$UNIT" --dry-run >&2 || true`.
4. Rejected plan: no script records one (`plan-tier.sh` picks the tier; a judge's NO-GO via `seat.sh collect --on-nogo`
   leads to the one revision, not a rejection). The owner's ruling: the command in item 5, run by hand; no hook.
5. Docs: `templates/main-session.md` ~43, after "Commit the plan from `<unit>-plan`...": "The Builder's launch closes
   `<unit>-plan` and its panes; on a rejected plan run `bash scripts/plan-worktree-close.sh <unit>`. A REFUSED line names
   a file not yet on main." `templates/AGENT_STARTUP.md` ~33, `README.md` ~178: one clause each. `CHANGELOG.md`: one entry.
6. `scripts/worktree-setup.sh` `<wt> --print-settings` (~20): F = mktemp seeded `{}`, `exec 3>&1 >&2`, skip ~31 mkdir, ~37-41
   exclude writes, ~71 `pp_link_node_modules`; end `cat "$F" >&3`. Same `<wt>` path, as claudeMdExcludes names it.
## Decisions
- Rung 6 of the plugin's ponytail ladder (no `skills/ponytail/` here): one script copying STEP 5's three commands. Rejected: a shared `paths.sh` helper.
- Rejected plan: the hand-run command only, no hook (owner's ruling).
## Tests (red first; new `scripts/__tests__/plan-worktree-close.test.sh`, run by `scripts/run-shell-tests.sh`)
Fixture: `git worktree add` `<unit>-plan`, marked as seat.sh ~211 does, then the real `worktree-setup.sh` run on it (no hand-made
link or settings); `.gitignore` `node_modules/`, main a `node_modules/` dir; an `orca-ide` stub logs calls, removes, lists one pane.
- Marked, with only setup's output and an untracked plan identical to main's: pane closed, worktree gone, exit 0.
- Refused (exit 1, one `REFUSED:` line naming the path, worktree stays, no close or remove), one case each: a file main lacks; a plan edited after the commit; a staged
  revision, working copy restored to HEAD; `chmod +x` on a tracked 100644 file; `node_modules` linked elsewhere or dangling (`readlink` unchanged); settings plus
  `env.LOCAL_NOTE`; ignored `.env`, `.claude/briefs/draft.md`; a committed rename and a staged rename `a.txt` -> `b.txt` where main copied `a.txt` to `b.txt` and kept
  `a.txt` (r6 P2: names `a.txt`); with B `f=old` and both HEAD and main `f=new`, a staged `f=old`, and an unstaged `f=old` with the index at HEAD (r7 P1: names `f`).
- `--print-settings` leaves `find <wt> -exec ls -ld` and `info/exclude` byte-identical (r4 P1-a).
- The stub's `terminal close` writes `.claude/plans/late.md` (r4 P1-b): refused at check 2, `late.md` kept, no remove.
- The stub's `terminal close` exits 1 for the pane (r5 P1): exit 1, one `kept:` line naming the handle, no remove.
- Unmarked (a Builder unit's) or another unit's mark: untouched; `--dry-run` on a clean one prints `would close`; no close or remove.
- `builder-launch.test.sh`: a launch with a refused `<unit>-plan` exits 0, Builder pane opened, `REFUSED:` on stderr.
## Kept
seat.sh's mark, lock and reuse rule; STEP 5; `plan_ok`; the risky first call (no Builder yet, so no close).
## Not doing
No close at merge as a backstop (not ordered). No hook on judge verdicts. No PushProve change (its own unit).
## Risks
- Fails safe (refused, left in place): a stray ignored file (`__pycache__/`); settings setup now writes differently
  (plugin update, `COMMANDECK_WORKER_COMPACT_WINDOW`). A branch Orca keeps holds only what is on main.
- Not covered: an outside writer after check 2 (no pane is left). Uncollected judges lose their pane; RESUME holds `pp_builder_lock` through the close.
Planned size: 8 files (2 new), ~175 changed lines (script ~60, tests ~85, builder-launch ~6, setup ~8, docs ~8, changelog ~3).

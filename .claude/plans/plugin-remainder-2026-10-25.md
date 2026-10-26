# Plan: plugin-remainder-2026-10-25 -- the rest of the plugin port, the prompt cache per role, design-only passes, the review threshold

Tier: Standard
Order: the owner, 2026-10-25: build the remaining plugin work now as ONE unit, no part split, whatever the file count
or line caps say (the order overrides the size caps for this unit)
Closes: issue 348, issue 349, issue 356, issue 357, issue 358, issue 359, issue 360, issue 364, issue 365, issue 367 (item 3, the cache issue)
Closes (only when G19 is built): issue 366
- Planned size: 113 files, 4461 changed lines

(Revision 5: without G21, the gated item 9, the unit is ~105 files and ~4,211 changed lines; G21's 8 files and ~250
lines are an estimate until the host commit exists.)

Launch: new unit plugin-remainder-2026-10-25

LOCAL merge only, no push. Base: main `9ac91d3` (0.47.0; part A1 merged as `aa40679`). Every file:line below was
read on `9ac91d3`, 2026-10-25.

Public repo: no personal names, seat nicknames, host product name, host paths, ruling ids or `#<number>` issue
references in any shipped file, test, commit message or this plan (`ci/leak-words.txt`). Outside CHANGELOG.md a
plugin issue is written "issue N" and a host issue "host issue N". The batch brief (untracked) carries the `#` form
of the Closes line that `merge-unit-local.sh` parses.

Tests: changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), plus the files each group names
(the runner does not run a shared helper's callers' tests). No red-proof run, no `Mutation-verified:` line, no
test-timeout raise. Tests run on the PC (`run-shell-tests.sh` hands them off, 0.47.0). Every review finding, P0 to
P3, blocks the merge; done is a closing pass `VERDICT: GO` naming no finding (G19 changes that rule for LATER units
only, Decision G19-3).

Port rule (the owner's order): a host item merged on the host's local main is PORTED from the named host commit
(adapted to the plugin site, not redesigned). A plugin issue with no host commit is BUILT from its issue text, one
function or block per item, its comment naming the plugin issue, no plugin-only names inside the logic, so the host
can port it back.

Timed checks: `scripts/__tests__/builder-fresh-round.test.sh` (`timeout 10` at :46 :108 :177), `scripts/__tests__/doctor.test.sh`
(`timeout 60` at :211 :215 :222; file cap `# timeout: 240`), `scripts/__tests__/doctor-options.test.sh` (`timeout`
at :24 :29 :35 :37), `scripts/__tests__/merge-unit-local.test.sh` (file cap `# timeout: 240`),
`scripts/__tests__/install-lib-setup.test.sh` (`timeout 20` at :284, `timeout 10` at :298 :300; revision 5). No heavy fixture goes
into these: G12's RD4 case in builder-fresh-round, G17's doctor cases and G10's merge-gate case use the existing stubs
and go after the timed cases; G17's doctor-options edits change the existing cases at :11-18, which come before the
timed ones and add no fixture. The heavy fixtures (a real rebase and test run for issue 356, real worktree adds for
issue 357) go in `scripts/__tests__/builder-codex-pass-rebase.test.sh` and `hooks/__tests__/git-safety.test.sh`,
which have no time-bound check. `rg -n '\btimeout [0-9]'` on every other test file this plan edits matches only
command text inside test payloads (`hooks/__tests__/no-poll-loops.test.sh` :266, :349), 2026-10-25; on
`scripts/__tests__/merge-queue.test.sh`, `transcript-requests.test.sh`, `builder-codex-pass-class-return.test.sh` and
`main-watch-report-wake.test.sh` it matches nothing (re-run 2026-10-25, revision 1). Revision 2:
`scripts/__tests__/run-shell-tests.test.sh` (`timeout 30` at :24 :86 :94 :98 :109 :117 :122 :139 :143 :157 :169): G10's
live-table case goes after all of them, last in the file, and adds one small fixture test file;
`scripts/__tests__/seat-run-refused.test.sh` (`timeout` at :49, :51): G20 edits only the role loop at :40, before them,
no fixture; revision 3: G10's second live-table case (own-lane and skip records) also goes last, after the first,
with two small fixture test files; `scripts/__tests__/seat-launch-github.test.sh` (G20, :24 and :30) and
`scripts/__tests__/worktree-setup.test.sh` (G17's relay 5m case) match nothing (`rg -n 'timeout [0-9]'`, 2026-10-25,
revision 3); `doctor.test.sh`'s timed cases :211-224 are edited in place by G20 (role names and the :221 routing
fixture), adding no fixture, and G17's rewrite of :115-147 is before them; `plan-tier.test.sh`, `seat-launch.test.sh`,
`builder-launch-resume-from-plan.test.sh` and `install-lib.test.sh` match nothing (`rg -n 'timeout [0-9]'`,
2026-10-25). Revision 4: `scripts/__tests__/doctor-run.test.sh` (`timeout 60` at :15 :25 :29 :42): G17 edits only
the fixture line :37 in place, no fixture added, no case moved; `scripts/__tests__/plugin.test.sh`,
`plugin-option.test.sh`, `install-lib-setup.test.sh`, `transcript-requests.test.sh`,
`hooks/__tests__/dependency-addition-guard.test.sh` and the host's `units.test.tsx` match nothing (`rg -n
'\btimeout [0-9]|# timeout:'` and, for the tsx, `timeout|setTimeout`, 2026-10-25), so the new cache, update-skill and
merge-attempt cases and the per-project checker fixture (two small git checkouts) go where the plan names them.
Revision 5, CORRECTED: `scripts/__tests__/install-lib-setup.test.sh` has time-bound checks the `rg` above missed,
because they are written `$(command -v timeout) <n>`: the c6 case (`timeout 20`, :284) and the c7 cases (`timeout 10`,
:298, :300). G17's two main-TTL cases (five and two `setup.sh` runs on one configured fixture) go after :300, after
all three. `hooks/units-sources.test.tsx` is new (the ported host file plus the Closes case) and has none.
Any other edited test file: the Builder runs the same `rg` before adding a heavy case and, on a match, places it
after the timed ones.

Background runs (RD13): every test run, of any length, starts with Bash `run_in_background`, and so does every other
command that can run in the background; only quick reads stay in the foreground.

## Parts

One part, this unit. G5 was missed because it sat in part A2, which was never launched after part A1 merged.

## 1. Item map (twin, verdict, site, change, test)

| Item | Issue | Host twin | Verdict | Plugin site (~line, on `9ac91d3`) | Change | Test (file, case) |
|---|---|---|---|---|---|---|
| 1 | 359, 365 (G5) | `218bd2b1` 3183 part, `bb280530` | PORT | `scripts/seat.sh:412-416`; `templates/main-session.md` Details :40-64; `scripts/builder-codex-pass.sh:1143`, `:1153`; ponytail sites (G5) | planning text; the plan's claims after the diff; the ponytail add-on removed | `scripts/__tests__/builder-codex-pass.test.sh` "the review prompt places the plan's claims after the trace instruction"; `scripts/__tests__/worktree-setup.test.sh`, `scripts/__tests__/plugin-option.test.sh`, `scripts/__tests__/rules-audit.test.sh` (G5) |
| 1 | 356, 357, 358 (G8) | none | BUILD | `scripts/builder-codex-pass.sh:1034` `rebase_and_test`, suite :1070-1090, header :1361; `hooks/git-safety.sh:223-225`; `hooks/hooks.json:66` PostToolUse; `skills/worktreereview/scripts/collect.py:486`, `:904`; `render.py:210-211` | pre-review timing line; tmp-worktree ownership; count from the squash commit | `scripts/__tests__/builder-codex-pass-rebase.test.sh`, `hooks/__tests__/git-safety.test.sh`, `scripts/__tests__/worktreereview.test.sh` (G8) |
| 1 | 360, 364 part 2 (G9) | none | BUILD | `scripts/dashboard_alerts.jq:56-60` (the list closes :98); `hooks/agent-startup-context.sh:104-145`; new `templates/cos-order.md`, `scripts/cos-order-check.sh`; `docs/chief-of-staff.md` | pass-loop alert; five Chief of Staff rules and the order-file check | `scripts/__tests__/dashboard-alerts.test.sh`, `scripts/__tests__/cos-order-check.test.sh` (new), `hooks/__tests__/agent-startup-context.test.sh` (G9) |
| 1 | 349 (G10) | `c7aaf716`, `84118aa9`, `8fb27eff`, `fdb79064` | PORT | new `hooks/units.tsx`, `hooks/units-sources.ts` + tests; `hooks/hooks.json:2`; `.claude-plugin/plugin.json` options; `types/index.d.ts`; `docs/dashboard.md`; `scripts/merge-unit-local.sh` step 4, a new block after the check (:512); `scripts/paths.sh:1140-1151`, `:1164` (`pp_option` cases for the three units options); `scripts/run-shell-tests.sh:135-136`, `:155-165` (the live table) | the units mod as host main has it now, active in a set-up project, its views read from `unitsBand`/`unitsPane`/`unitsStatus`, its merge rows from the plugin's merge state, queue and log, its test rows from the runner's new live table, its planning seats from the seat records; its merge gate on every merge path | `hooks/units.test.tsx`, `hooks/units-sources.test.tsx`; `scripts/__tests__/merge-unit-local.test.sh`, `scripts/__tests__/merge-queue.test.sh`, `scripts/__tests__/run-shell-tests.test.sh`, `scripts/__tests__/plugin-option.test.sh` (G10) |
| 1 | 348 (G11) | none | BUILD | new `.github/workflows/release.yml`, `scripts/release-decide.sh`, `scripts/release-notes.sh`, `scripts/release-backfill.sh`; `scripts/update.sh:27` | workflow and scripts only; nothing runs, tags, publishes or writes notes in this unit | `scripts/__tests__/release-notes.test.sh` (new) (G11) |
| 1 | drift R1-R24 (G12) | host rule text | PORT | RD1-RD13 sites (section "Rule drift items") | rule text, one routing value | `scripts/__tests__/brief-template.test.sh`, `scripts/__tests__/builder-codex-pass.test.sh`, `scripts/__tests__/builder-fresh-round.test.sh`, `scripts/__tests__/install-lib-setup.test.sh` (G12) |
| 3 | 367 (G17) | none | BUILD (new design) | `.claude-plugin/plugin.json:240-253`; `scripts/paths.sh:1146`; `scripts/setup.sh:12`, `:37-39`, `:55`, `:119`, `:213-214`, `:394`, `:399`, `:414-415`, `:478`, `:493`, `:495`, `:629`; `scripts/install-lib.sh:271-289`, `:396-430`, `:493-525`; `scripts/worktree-setup.sh:100-102`, `:166-170`; `scripts/builder-cache-check.sh:2-8`, `:12`, `:26-28`; `skills/setup/SKILL.md:198-205`; `skills/update/SKILL.md:29`; `docs/cost-control.md:14-16`; docs; `README.md:118`, `:258-259` | three roles, each `5m \| 1h \| leave`; main's value only in main's `--settings` file; the cache checker proves the worker answer | `scripts/__tests__/install-lib-setup.test.sh`, `scripts/__tests__/install-lib.test.sh`, `scripts/__tests__/worktree-setup.test.sh`, `scripts/__tests__/doctor.test.sh`, `scripts/__tests__/doctor-options.test.sh`, `scripts/__tests__/transcript-requests.test.sh`, `hooks/__tests__/no-poll-loops.test.sh`, `scripts/__tests__/plugin.test.sh` (G17) |
| 4 | none (host order) | `55126a9c` | PORT, the missing part only | `scripts/builder-codex-pass.sh:103` (`FORMAT`) | the reviewer writes a `Class search: rg ...` line under each blocking finding | `scripts/__tests__/builder-codex-pass-suite.test.sh` "the pass prompt asks for a Class search line under each blocking finding" (G15) |
| 5 | none (host order) | `95730a8d` | PORT | `scripts/builder-codex-pass.sh:152-154`, `:194`, `:312`, `:423`, `:569-577`, `:964`, `:1066-1067`, `:1121`, `:1361-1366`, `:1448`; `scripts/main-watch.sh:928-934`, `:1250`, `:1268` | a final whose commit changes no code is a design-only pass that merges nothing | `scripts/__tests__/builder-codex-pass-closing.test.sh`, `scripts/__tests__/builder-codex-pass-class-return.test.sh`, `scripts/__tests__/main-watch-report-wake.test.sh` (G16) |
| 6 | 366 (G19, gated; second to last) | host unit review-threshold-2026-10-25 (in planning; not on host main) | PORT after the host commit lands | `scripts/builder-codex-pass.sh` `FORMAT` :103, `session_proof` :194-340, `round_files` :357, `earlier_passes` :515, `--verify` :548-600, prompt `REST` :1153; `scripts/merge-unit-local.sh` steps 1 and 3 | severity threshold, cap 5, P0/P1 never capped, fresh closing reviewer, file then merge | `scripts/__tests__/builder-codex-pass-threshold.test.sh` (new) (G19) |
| 7 | none (host order) | `24187ab2` | PORT | `hooks/hooks.json:104`; `docs/hooks.md:35`; `hooks/cos-unfinished-stop.sh:1-7` | unregister the Chief of Staff unfinished-work Stop hook; script and test stay | `scripts/__tests__/plugin.test.sh` "the Chief of Staff unfinished-work Stop hook is not registered, and its script stays executable" (G18) |
| 8 | none (the owner's order, revision 2) | `abe1f341` (host main, 2026-10-25) | PORT, adapted | `config/routing.json:46-63`; `.claude-plugin/plugin.json:128`, `:157-187`; `scripts/plan-tier.sh:37-38`; `scripts/builder-launch.sh:157`; `scripts/codex-helpers.sh:51`; `scripts/setup.sh:268`; `skills/setup/SKILL.md:155-156`, `:161`; `templates/main-session.md:65`; `docs/configuration.md:20`; `README.md:111`, `:244-248` | the Panel's second plan judge is `plan-judge-fable`, a read-only Claude seat on fable at high; the Astra judge role and its five options go | `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/plan-tier.test.sh`, `scripts/__tests__/seat-launch.test.sh`, `scripts/__tests__/seat-launch-github.test.sh`, `scripts/__tests__/seat-run-refused.test.sh`, `scripts/__tests__/builder-launch-resume-from-plan.test.sh`, `scripts/__tests__/install-lib-setup.test.sh`, `scripts/__tests__/plugin-option.test.sh`, `scripts/__tests__/doctor.test.sh` (G20) |
| 9 | none (host order, revision 3) | host unit builder-speed-2026-10-25 (plan being written; not on host main) | PORT after the host commit lands (gated, LAST) | `templates/_builder-brief-template.md:94-105`; `scripts/builder-codex-pass.sh` fix brief :1426-1470; `hooks/hooks.json` PreToolUse/PostToolUse/Stop lists; the hook scripts the judged host plan changes | the post-fix checks run at once and each exit code is reported; per-call hook overhead cut with no check removed or weakened | from the judged host plan; every existing `hooks/__tests__/<hook>.test.sh` of a changed hook stays green (G21) |

## 2. Groups

Every Decision is in section "Decisions" with its `Test:` line. Every new conditional write or safety check has a
`Break:` line; the order forbids red proofs, so each `Break:` line is the target a reviewer checks by reading (does
the named test fail if the named condition is removed?). Every new flow step has a `Catches:` line. G5, G8, G9, G10,
G11 and G12 are the judged groups of `.claude/plans/plugin-port-2026-10-25.md`, copied with their decisions, sites,
tests and rows, each line re-read on `9ac91d3`; a line marked CORRECTED differs from the judged text because the code
says otherwise (section "Plan change log").

### G5 -- planning text and the ponytail removal: issues 359, 365 (host `218bd2b1` 3183 part, `bb280530`)

- 359, 1-3: the plan-author lines (`scripts/seat.sh:412-416`; A1 already added the size, `Test:`, `Break:` and What
  can go wrong line at :416) and `templates/main-session.md` Details (:58-64, where main writes the plan specs): a
  What can go wrong table (case / input or starting state / expected result / test name; at most five; "checked,
  none" when empty; each row's test in the acceptance tests); every `[likely]`/`[uncertain]` claim settled (command +
  output) or a Builder check before the dependent cut, with the action per outcome; each cut lists Produces and
  Consumes and every existing consumer of a contract it changes.
- 359, 4: accepted judge findings are written into the plan before the Builder starts, one `## Plan change log` line
  each; the judge rechecks only what changed. `templates/_builder-brief-template.md`: before the first edit, one
  table of cut pairs sharing a file or symbol; a finding whose root cause is the plan amends the plan first, then the
  code.
- 359, 5: main's judge-spec lines (Details :58-64): read the plan as a Builder who cannot ask and list every place a
  wrong guess would change the code; try to falsify each checkable claim. CORRECTED: `REST`
  (`builder-codex-pass.sh:1153`) carries no plan claims today; only the plan's What can go wrong reaches the reviewer
  (`CASES`, :1143, an awk over the plan). So 5c adds one block: `plan_section <heading>` is :1143's awk made a
  function (`CASES` calls it), and `CLAIMS` (the plan's `## Claims to falsify` and `## Decisions`, under a
  `CLAIMS_HEAD` saying "claims to falsify, not facts") is appended to `REST` AFTER `$DIFF`, so the reviewer reads the
  trace instruction (the angle text, :144) and the diff first (Decision G5-3).
- 365: delete `templates/global-rules.md:5` and the last sentence of `:89-91`; reword `:55-58` (the comment-tag rule
  stays; "even when the ponytail skill asks for a tag" goes, the skill being gone); `templates/ponytail/` (3 files);
  the `ponytail` option (`.claude-plugin/plugin.json:226-232`, `scripts/paths.sh:1143`, `:1162`); `config/addons.tsv:6`;
  `scripts/builder-launch.sh:291-294` and `templates/_builder-brief-template.md:26` (`{ponytail}`); `scripts/setup.sh`
  (:12, :36, :119, :212, :351-361, :383, :393, :464-470, :475-477, :482, :505, :625-627, and `--ponytail` in
  `TAKES` :55); `scripts/install-lib.sh:493-499` (main's lean list drops both ponytail keys); `skills/setup/SKILL.md:192-197`
  (question 11; later questions renumbered) and `:221` (the add-on line's ponytail clause); `skills/uninstall/SKILL.md:18`;
  `hooks/dependency-addition-guard.sh:3`, `:42`, `:278` ("Rule 2 / ponytail" becomes "Rule 2", as the host commit
  has it); docs `add-ons.md:6-7`, `:21`, `commands.md:38-41`, `setup-questions.md:23`, `worker-panes.md:11-12`, `:17`,
  `:32`, `uninstall.md:27`, `configuration.md:48`, `:57`; NEW on re-read: `README.md:117`, `:141`, `:257` (the
  ponytail rows) and `:314` (the retired-flag row says the add-on is removed); `NOTICE:11-15` (the bundled skill's
  attribution goes with the files), `:42` (its "one exception" clause) and `:52-53` (the full plugin leaves the add-on
  list).
- 365, the worktree-setup caller: `scripts/worktree-setup.sh` reads the removed folder at :73 (exits the script under
  `set -e` once the folder is gone) and the removed option at :197. Both go, with `PONY` (:198-199), the `--argjson
  pony`/`--arg sum` inputs (:200) and the add branch at :224. The summary-hook cleanup stays and becomes the only
  ponytail logic: the filter at :78 and the `$sumhook` block at :207-209 match the old command by its
  `/templates/ponytail/SUMMARY[.]md"$` tail, so a rerun on a worktree set up before 0.48.0 drops that hook command (an
  owner hook in the same registration stays) and the off leaf the run wrote beside it. The relay branch's
  `del(.["ponytail@ponytail"])` (:103) stays (it removes an off an earlier run wrote). The lean-pane report line
  (:227) drops its ponytail part; the comments at :21, :72, :97-98 and :186-194 lose the summary wording.
  Catches: a worktree whose SessionStart hook would `cat` a deleted file on every start.
  Break: scripts/__tests__/worktree-setup.test.sh -- a rerun on a worktree set up with the summary hook drops that hook and its off leaf and keeps an owner hook beside it -- scripts/worktree-setup.sh:~207 the $sumhook test
- 365, option tests: `scripts/__tests__/plugin-option.test.sh` (22 ponytail lines) uses `ponytail` as its "level"
  example (:6 comment, :25, :32, :38-39, :42, :49-52): those cases go with the validation branch (`paths.sh:1162`);
  the picker (`builderEffort`) and number (`dashboardPort`) cases still cover each source. :28 ("another plugin's
  options are never read") moves to `builderEffort`. In the pre-fill cases (:201-242) `ponytail` is only a key name:
  it becomes `relayPromptCacheTtl` (`"leave"`), a key G17 keeps (Decision G5-5). The fixture's `other@elsewhere`
  options keep their `ponytail: true` (another plugin's key, never read).
- `scripts/__tests__/plugin.test.sh`: the option-table row :67 and the bundled-skill checks :208-216 go; the option
  count (:76, 39) follows section "Contracts". Other tests asserting ponytail (`rg -c -i ponytail`: install-lib-setup
  13, profile-revoke 13, profile-settings 11, install-lib 4, rules-audit 5, update 2, dependency-addition-guard 1,
  worktree-setup 53, brief-template 1) change only where they assert the removed behaviour; a fixture that merely
  names the third-party plugin in `enabledPlugins` or as another plugin's option stays.
- Existing installs: `config/retired.tsv` is a lint list only (reader `scripts/instruction-lint.py:80`); its
  `--no-ponytail` row's replacement becomes "nothing: the add-on is removed" and one row lints `--ponytail` the same
  way. Installs carrying a saved `ponytail` answer: 0 on this machine (no `~/.commandeck/install/`, no `ponytail` key
  in either project `commandeck.json` or a profile's `pluginConfigs`, checked 2026-10-25); elsewhere unknowable. No
  cleanup of an existing install (Decision G5-2, section "Question for the owner").

### G8 -- issues 356, 357, 358

- 356: CORRECTED: the plugin's pre-review steps are the rebase and its touched tests (`rebase_and_test`, :1034-1066)
  and the full suite (:1070-1090, which already times itself into its `Suite:` line); there is no separate precheck
  step. Each step is timed with `SECONDS`; the round file header (:1361, beside `Timing:`) gains `Pre-review: rebase
  <s> s, tests <s> s, suite <s> s` (a step not run says `not run`) (Decision G8-2).
- 357: `hooks/git-safety.sh`. REDESIGNED in fix round 2 (the class stale-worktree-owner came back in passes 1 and
  2) and again in fix round 4 (pass 4: a record step that ran late claimed a worktree another session had put at
  the path since; the sweep: `git --version worktree add P` passed the fence, exited 0 and added nothing). Ownership
  is proved by one add's own exit status AND a claim that no hooked add of the path began after it. One fence, a
  fixed list in place of a parser: the whole command is `git [-C <dir>] worktree add
  [-q|--quiet|--detach|--no-checkout|-b <name>|-B <name>]... <path> [<commit>]` or `git [-C <dir>] worktree remove
  (-f|--force)... <path>`, every word of `[A-Za-z0-9_./~@^:+=,-]`, joined by spaces or tabs: no other git option
  (`--version`, `--exec-path` and the like print and exit 0 with no add), no second call, no `;`, `&`, `|`,
  newline, `!`, quote, `$`, backtick, bracket, brace or redirection. For such a command the call's exit status is
  the command's, so Claude Code's PostToolUse (fired only for a call that exited 0; a non-zero exit fires
  PostToolUseFailure, checked 2026-10-26 with `claude -p` running `false` and `true`) means git's add itself
  succeeded, and git's add fails on a path that holds anything (an existing worktree, a file, a non-empty folder).
  The path is absolute or `~/`, canonical, under `${TMPDIR:-/tmp}`, `/tmp` or `/private/tmp`.
  - PreToolUse (`hooks/hooks.json:41`) of a fenced add of P, when P does not exist: writes the claim
    `<parent of P>/.commandeck-add.<name of P>`, this session's id, as a temp file in that folder moved over the
    claim with one `mv -f` (the parent made if missing; git would make it). P existing: nothing written (the add
    will fail). The hook never deletes a claim. No other scratch state (the `pending` line and
    `$PP_SCRATCH/tmp-worktrees` stay gone).
  - PostToolUse Bash (`hooks/hooks.json` PostToolUse :66, `git-safety.sh --record-add`): the command is a fenced add;
    the claim beside P holds this session's id; P is now a linked worktree whose toplevel is exactly P; and `git
    worktree list --porcelain` names P exactly once. Then it writes the session id into `commandeck-owner` in that
    worktree's own git dir (`<common dir>/worktrees/<name>/`), once (noclobber).
  - A forced remove is allowed only when the command is a fenced remove (so no other call runs between the check
    and the remove) and the grant at that path holds this session's id; every other forced remove is blocked as
    today. No `session_id` (a Codex pane): nothing written, blocked as today.
  - Reset: git deletes the worktree's git dir on `remove`, on `prune`, and on `add -f` over a missing registered
    entry, and a new add makes a new folder, so a grant never outlives its worktree. A claim stays until the
    temporary folder is cleaned; alone it grants nothing. Retry: a forced remove with no grant (a record step that
    never ran or ran late, a claim or grant file deleted, an add outside the fence) is blocked whatever the reason,
    and the block message names the one retry: a plain `git worktree remove <path>`, which this hook never blocks and
    git refuses only while the worktree holds changes.
  Catches: a forced remove of a tmp worktree another session owns, whose path this session's failed, masked or
  no-op add named, or which replaced this session's removed worktree before or after this session's record step, or
  which another session put there after the check.
  Break: hooks/__tests__/git-safety.test.sh -- forced removal of a worktree the session did not create stays blocked -- hooks/git-safety.sh wt_owned's grant test
  Break: hooks/__tests__/git-safety.test.sh -- every ownership ordering found so far, in order -- hooks/git-safety.sh the fixed-list test in --record-add
  Break: hooks/__tests__/git-safety.test.sh -- every ownership ordering found so far, in order -- hooks/git-safety.sh the claim test in --record-add
  The new registration raises the hook list by one: `docs/hooks.md` gains its row. `scripts/__tests__/plugin.test.sh`
  has no hook count (read :133-150 on `9ac91d3`: it checks every registered path, not a number), so nothing there.
- 358: `collect.py` `lines_changed()` (:486) returns None when the worktree is gone, and merge step 5 removes it
  (`merge-unit-local.sh:160`). When the worktree is gone, count the unit's squash commit on main (`git show --numstat
  --format= <sha> -- . ':(exclude).claude/briefs'`), its sha per A5. `render.py:210-211`: None prints `Lines changed:
  not recorded (<why>)`.

### G9 -- issue 360, issue 364 part 2

- 364 part 2 (BUILD): `dashboard_alerts.jq` gains, beside the `stage-` rule (:56-60, inside the list that closes at
  :98), `pass-loop-<project>/<unit>-r<N>` when a live unit's newest pass is 4 or more and NO-GO, with its top
  findings. `cos-watch-alerts.sh` already wakes the Chief of Staff once per new alert id; with no Chief of Staff, main
  hears every finished report through 0.47.0's report wake.
  Break: scripts/__tests__/dashboard-alerts.test.sh -- a pass-4 NO-GO raises pass-loop once and a GO raises none -- scripts/dashboard_alerts.jq the pass-loop select
  Catches: a unit looping on review rounds with nobody told while each pass still posts its own report.
- 360 (BUILD): the Chief of Staff block in `hooks/agent-startup-context.sh` (:104-145) gains the five rules (scope is
  the owner's words; additions under `## Chief of Staff additions -- NOT ordered`; one multi-select prompt, decoy
  first; no bundle approvals; at a pass-loop alert for pass 4 or more, or a class stop, tell the owner which part of
  the scope produces the findings and whether the owner's words asked for it). Pass 1 (the owner's later issue-360
  comments): the alert is reported from pass 4, and with no relay pane `templates/main-session.md` gives main the same
  five rules; the plan author writes an `Owner's words:` line and each plan judge flags a requirement that does not
  trace to it (`scripts/seat.sh` spec text). New `templates/cos-order.md` (two
  headings); new `scripts/cos-order-check.sh <file>` flags a file whose first section is not `## The owner's words`,
  or with additions outside the NOT-ordered heading; the rule says run it before sending an order file to main.
  `docs/chief-of-staff.md` gains a short section.
  Break: scripts/__tests__/cos-order-check.test.sh -- an order with an addition outside the NOT-ordered section is flagged -- scripts/cos-order-check.sh the section test
  Catches: a Chief of Staff addition passed to main as if it were the owner's words.

### G10 -- the units mod: issue 349 (host `c7aaf716`, `84118aa9`, `8fb27eff`, `fdb79064`)

Port the host mod as host main has it now (`fdb79064`, the last commit touching it, 2026-10-25): the v2 layout, no
stall mechanic (owner, issue 349 comments), issues built from `8fb27eff` (once the Build step is done every issue
counts as built, `builtOf`; the stage key is the one the plugin's dashboard writes, `review`, at
`scripts/dashboard_builders.jq:71`, in both STAGES and stepsOf's `late` map; its test "issues built count the evidence
while building and every issue once the build is done"), and `fdb79064` (the band lists running merges only; a
stopped or refused merge shows in the side pane and `/units`; its test "a refusal shows its step and reason in the
pane and /units, and nothing in the band").
- Files, from host main: `hooks/sources.ts` -> `hooks/units-sources.ts` (367 lines, under the 500 `.ts` cap of
  `hooks/file-size-cop.sh:59`), `hooks/units.tsx` (299), `hooks/units.test.tsx` (381), `hooks/sources.test.tsx` ->
  `hooks/units-sources.test.tsx` (103); each `.tsx` under 400. `hooks/hooks.json:2` modules gains `./units.tsx`.
- Manifest: `unitsBand`, `unitsPane`, `unitsStatus` in `.claude-plugin/plugin.json` (`auto|on|off`; `auto` is on in
  main and the Chief of Staff and off in worker and reviewer panes; the status option's description says "a verdict
  or a merge"). No stall option. `/units` and `/units <view> on|off`. `types/index.d.ts` gains the atom shapes.
- Option readers (revision 2, Decision G10-8). Host `units.tsx:233` reads `options.band`, `options.pane`,
  `options.status`; the plugin's keys are the manifest's, so that line reads `options.unitsBand`,
  `options.unitsPane`, `options.unitsStatus` (each `?? 'auto'`), and the mod keeps its internal `band`/`pane`/`status`
  names. That also satisfies `plugin.test.sh:42-46`'s reader check, which greps `options\.<key>` in `hooks/*.tsx`;
  the check stays as it is. The doctor: `il_options_report` (`install-lib.sh:432-438`) calls `pp_option` for every
  manifest key, and `pp_option` dies `no option` (`paths.sh:1151`) on a key it has no case for, so `pp_option` gains
  `unitsBand) p=.units.band d=auto ;; unitsPane) p=.units.pane d=auto ;; unitsStatus) p=.units.status d=auto ;;` and a
  check beside `autoDecideSeats`' (:1164): `unitsBand|unitsPane|unitsStatus) case $v in auto|on|off) ;; *) src=default
  v=$d ;; esac ;;`. No shell script reads them; the doctor shows them.
  Tests: `scripts/__tests__/plugin-option.test.sh` (after its existing cases) "unitsBand, unitsPane and unitsStatus
  read auto by default, a /config off as off, and a value they do not take as auto"; `hooks/units.test.tsx`: the
  host's "config and the command each toggle each view" with `quiet` as `{ options: { unitsBand: 'on', unitsPane:
  'on', unitsStatus: 'on' } }`, and a new case after it, "unitsBand, unitsPane and unitsStatus off in config show no
  band, no pane and no status line in main" (`{ unitsBand: 'off', unitsPane: 'off', unitsStatus: 'off' }`, seat
  `main`, one live unit: no band row, nothing opened, no status). `doctor-options.test.sh`'s option count (:16)
  follows the manifest unchanged.
  Break: hooks/units.test.tsx -- unitsBand, unitsPane and unitsStatus off in config show no band, no pane and no status line in main -- hooks/units.tsx register's options.unitsBand / unitsPane / unitsStatus reads
- Activation guard (revision 2, Decision G10-7). Host `units.tsx:240` returns before registering anything unless
  `${seat.main}/.claude/units-mod/hooks/units.tsx` exists, a host-local file; in the plugin that file never exists,
  so the shipped mod would stay inactive everywhere. The plugin's guard is a set-up Commandeck project: the main
  checkout has `.claude/commandeck.json` (the file setup writes and `hooks/autodecide.tsx:60` already reads); the
  same `$.fs.stat` call on that path, the rest of the line as the host has it. The comment above it says "Registers
  nothing outside a Commandeck project". Test fixture: `world()` (host `units.test.tsx:28-32`) writes
  `${MAIN}/.claude/commandeck.json` (`{"version": 1}`) when `installed`, in place of the host-local file; the host's
  case for a checkout outside the host project becomes "a checkout with no Commandeck setup registers nothing"
  (installed false: no command, no pane, no status, no `bash` run).
  Catches: a mod that ships in the plugin and draws nothing in any project because it looks for a host-only file.
  Break: hooks/units.test.tsx -- a checkout with no Commandeck setup registers nothing -- hooks/units.tsx the commandeck.json stat in session.start
  Test: `hooks/units.test.tsx` every other case runs with `installed` true and so proves the mod registers in a set-up
  project (e.g. "main and Chief of Staff default on, worker and reviewer default off: main").
- README -> a units section in `docs/dashboard.md` (the host README's text without the stall lines, paths the
  plugin's). tsconfig: the plugin root's `tsconfig.json` already extends `./.claude-plugin/types/tsconfig.json` and
  covers `hooks/` (`hooks/autodecide.tsx` builds under it); nothing to add.
- Adapted, not redesigned: the snapshot is `$HOME/.commandeck/dashboard/data.js` (`dashboard.sh:43`, `OUT`); the
  host's push-chain lanes and long-job locks are dropped (the plugin has neither). No stall producer. Merge rows come
  from the adapter below; test rows and planning seats from the two sources after it.
- Snapshot adapter (revision 3, Decision G10-1). Host `parseSnapshot` (host `sources.ts:148-188`) needs top-level
  `units.inFlight` (an array, else `units: snapshot unreadable`) and reads merge times from `mergedSincePush[].mergedAt`.
  The plugin's `data.js` holds `window.DASH = {updatedAt, home, name, sources, projects, ...};` (`dashboard.sh:1197-1200`),
  each project's object under its name (`{($n): (add + {path, workspaces})}`, :1144, `$n` the project's `PP_PROJECT`),
  its `units` part from `units()` (:293, output :473-488). So a filename change alone leaves every plugin snapshot
  unreadable. The port:
  - `loadPaths` (G10's merge-state adapter below) also prints `PP_PROJECT`, set as the dashboard sets it
    (`. <plugin root>/hooks/lib/project.sh; pp_project "$PP_MAIN"`, as `dashboard.sh:39` does), as a new `project`
    field of `Paths`. `readSnapshot` (host `units.tsx:58-68`) passes it: `parseSnapshot(base.text, now, p.project)`.
  - `parseSnapshot(text, now, project)` parses the text as the host does (the `window.DASH =` prefix and the `;` are
    stripped by the host's regexes, which also take `window.DASH={...};` with no spaces). Then `const p =
    j?.projects?.[project]`; not an object: `emptySnap('units: this project is not in the dashboard snapshot')`. `const
    u = p.units`; `u?.inFlight` not an array (the plugin writes `inFlight: null` when it cannot stamp stages, :473):
    the host's `emptySnap('units: snapshot unreadable')`. Every later host read of `j.units.<x>` reads `u.<x>`.
  - Field by field, host read -> plugin source (read on `9ac91d3`):

    | Host reads | Plugin snapshot | Plugin producer |
    |---|---|---|
    | `j.updatedAt` (stale minutes) | `j.updatedAt`, top level, unchanged | `dashboard.sh:1197` |
    | `j.units.inFlight[]` | `j.projects[project].units.inFlight[]` | :473-480 |
    | row `.unit`, `.stage`, `.round`, `.ageSec`, `.agents` | the same names | row object :428 |
    | row `.builder.verdict`, `.builder.verdictRound` | the same | :394 |
    | row `.builder.findings` (`.sol ??` itself), `.builder.issues`, `.builder.built` | the same (`builder_progress`) | :253, :412 |
    | row `.builder.startedAt`, `.builder.cost.stages[].{stage, usd}` | the same | :383, :474-477 |
    | `j.units.mergedSincePush[].unit`, `.mergedAt` | `...units.mergedSincePush[].unit`, `.at` (ISO-8601 UTC); `null` with no upstream reads as `[]` | :483, `finished_builds` :516-518, `at` written by `merge-unit-local.sh:601` |
    | `j.units.finishedBuilds[].cost.total.usd` | `...units.finishedBuilds[].cost.total.usd`; `null` reads as `{}` | :484 |
    | `j.mainChain.chain` | none (the plugin's `mainChain`, :665-675, has `commits`, `unpushed`, `lastMerge`): `chain: null` always | dropped lane |

    So the only renamed field is `at` for `mergedAt`: `const merged = (u.mergedSincePush ?? []).map((m: any) => ({
    unit: String(m.unit), at: Date.parse(m.at ?? '') }))`. The stage names are the plugin's own (`building`,
    `review`, `fixing`, `planning`), which the host's `STAGE_COST` and `NOT_UNITS` already use. No other mod code
    reads the snapshot.
  - The ported `hooks/units-sources.test.tsx` snapshot cases and `hooks/units.test.tsx`'s `world()` snapshot writer
    use the plugin envelope (`{updatedAt, home: 'p', projects: {p: {path, units: {...}}}}`, project `p`), so every mod
    case reads the plugin's shape; none keeps the host's top-level `units`.
  Catches: a mod that reads every real plugin snapshot as unreadable and never shows a unit merged today.
  Test: `hooks/units-sources.test.tsx` "a plugin snapshot's project units, merge times and costs parse": the judge's
  input as written, `window.DASH={"updatedAt":"2026-10-25T20:00:00Z","home":"p","projects":{"p":{"path":"/repo","units":{"inFlight":[{"unit":"u","stage":"building"}],"mergedSincePush":[{"unit":"v","at":"2026-10-25T19:00:00Z"}]}}}};`,
  project `p`, now `Date.UTC(2026, 9, 25, 20, 1)`: note null, one row (`u`, `building`), `merged` `['v']`, `mergedAt`
  `[{unit: 'v', at: Date.UTC(2026, 9, 25, 19)}]`, `chain` null, `finishedUsd` `{}`; and "a snapshot without this
  project, or with no unit list, draws nothing and says why" (project `q` on the same input: `units: this project is
  not in the dashboard snapshot`; `inFlight: null`: `units: snapshot unreadable`). `hooks/units.test.tsx` "a unit
  merged today from a plugin snapshot shows in the pane's merged-today line" (the world's snapshot with
  `mergedSincePush: [{unit: 'v', at: <today>}]`).
  Break: hooks/units-sources.test.tsx -- a plugin snapshot's project units, merge times and costs parse -- hooks/units-sources.ts parseSnapshot's projects[project].units read and its m.at merge time
- Test progress (revision 2, Decision G10-9; issue 349's "Scope added" asks for live test progress and allows a
  producer where the runner writes none). Host `readTests` (host `units.tsx:132-170`) reads two things: the host's
  test logs under `${tmp}` (named after the host), which only the host's node and web test wrappers write (the plugin has neither:
  that half is dropped), and the runner's live table `<git dir>/<host name>-test-live/<pid>.tsv`
  (`run <epoch> <jobs>`, `file <rel>`, `start <rel> <epoch>`, `end <rel> <ok|FAIL|skip> <secs>`; parser host
  `sources.ts:76-88`, `parseTestLive`, ported unchanged). The plugin's `run-shell-tests.sh` writes no such table: its
  results live in `$RES` (`mktemp -d`, :135) and on stdout (:164). Producer, ported from host `run-shell-tests.sh:156-161`:
  after `RES=` (:135), `GD=$(git rev-parse --absolute-git-dir 2>/dev/null) && mkdir -p "$GD/commandeck-test-live"
  2>/dev/null && LIVE=$GD/commandeck-test-live/$$.tsv || LIVE=`; the trap at :136 also removes `$LIVE`; `live()` is the
  host's one-printf, tab-joined writer that never fails the run. CORRECTED (revision 3): skips and exclusions are
  decided outside `run_one`, in the launch loop (:179-198: a `# parked:` file and, without `--own-lane`, an own-lane
  file are skipped at :184-191; under `--own-lane` an ordinary file is excluded, `EXCL[i]=1` at :187), so the host's
  selection pass is ported with the table (host `run-shell-tests.sh:210-235`): the loop is split into a selection
  pass that sets `REL[i]` (the file's physical path less `$ROOTP/`, :115), `SEL` (every file not excluded, skipped
  ones included) and `RUN` (the files to launch), printing today's `-- skip` line where it does now; an excluded file
  enters neither `SEL` nor the table, and keeps `EXCL[i]=1` for the report as today. Then `live run <epoch> <jobs>`,
  one `live file <rel>` per `SEL` file, one `live end <rel> skip 0` per skipped `SEL` file, and the launch pass over
  `RUN` (the `jobs -rp` wait unchanged). All of it runs after the hand-off to the PC (:120-133), so a file run on the
  PC is not listed. `run_one` (:155-165) writes `live start "${REL[$1]}" <epoch>` before and `live end "${REL[$1]}"
  <ok|FAIL> <secs>` after its file, the word being the first of its `status_line` (host :185, :195). The report pass
  is unchanged. The mod's `readTests` keeps only the table half: it lists
  `${gitDir}/commandeck-test-live/*.tsv` (owner `main`) and `${gitDir}/worktrees/<w>/commandeck-test-live/*.tsv`, a
  table counting while its pid (the file name) is alive (`ps -o pid= -p`, as the host). The owner of a worktree table
  is the host's `ownerOf` of the path in `${gitDir}/worktrees/<w>/gitdir` (less its `/.git`): a unit's worktree under
  `$PP_WORKSPACES` is that unit, and anything else (the merge's own copy of the merged tree, `merge-unit-local.sh`'s
  `mktemp -d`) is skipped, so a merge's check draws no second row. The merge row's own counts come, as on the host,
  from the `-- ok`/`-- FAIL` lines the check prints into the merge log (`parseMergeLog`); the plugin's log has no host
  `STEP 2 tests:` total line, so `counts` (host `sources.ts:193`) prints `<done> files` with no total, unchanged code.
  Catches: a standalone test run, a Builder's tests or a merge's check running for minutes with no progress in any
  view, because the plugin's runner wrote nothing a mod can read.
  Tests: `scripts/__tests__/run-shell-tests.test.sh` (last, after its timed cases) "a run's live table lists its
  files while they run and is gone when the run exits" (a fixture test file copies `$(git rev-parse
  --absolute-git-dir)/commandeck-test-live/*.tsv` to `$TMP/seen` while it runs; after the run `$TMP/seen` holds a
  `run` line, a `file` line naming it and its `start` line, and the folder holds no `.tsv`); after it, last in the
  file (revision 3), "a skipped own-lane file finishes as skip in the live table, and under --own-lane the ordinary
  file it leaves out never enters it" (two fixture files, `ord.test.sh` and `lane.test.sh` with `# own-lane:
  fixture` in its first lines, each copying the table to `$TMP/seen-<name>` when it runs. Run 1, no flag: `seen-ord`
  holds `file` lines for both, `end <lane rel> skip 0` before `start <ord rel>`, so the table's total is 2 with 1
  finished before any launch. Run 2, `--own-lane` on the same pair: `seen-lane` holds `file <lane rel>` and its
  `start`, and no line naming `ord.test.sh`, so the total is 1. After each run the folder holds no `.tsv`).
  `hooks/units.test.tsx`
  (plugin-shaped fixtures: tables at `${MAIN}/.git/commandeck-test-live/<pid>.tsv` and
  `${MAIN}/.git/worktrees/u/commandeck-test-live/<pid>.tsv` with `${MAIN}/.git/worktrees/u/gitdir` holding
  `${WS}/u/.git`; no host test log in any case): "a standalone run-shell-tests run shows files done and first
  failure in the pane and /units, and one test run in the band" (revision 5: two `file` lines, one `end ok`, one
  `end FAIL`, pid live. The table reader sets `kind: 'shell'` (host `units.tsx:164`), and the host's renderers
  print: `/units` and the pane contain `▸ u  shell 2/2 files · 1 failed (first <the FAIL file>)` (host
  `sources.ts:272`, `counts` :193, elapsed right-aligned after it); the band contains `▸ 1 test run` (host
  `bandModel`, `sources.ts:322`, as host `units.test.tsx:128` asserts) and not `2/2`); "a merge check's test lines show files done and the first
  failure in its merge row, and its tmp copy's table draws no test row" (a live merge state, the log holding `STEP 4
  check: ...`, `-- ok   a.test.sh 1s`, `-- FAIL b.test.sh 2s`, and a live table under a worktree whose `gitdir` is
  under `${TMP}`: `◐ u  tests 2 files · 1 failed (first b.test.sh)` and no `▸` row); the host's "one unreadable test
  log or live table leaves the other test rows and names the unreadable ones" keeps only its table half (`tests
  99.tsv: table unreadable`); "a stopped merge does not hide the next standalone test run of that checkout" with its
  test run as a table; "mid-run merge and test logs show step and counts in /units and the status line" with the
  merge from the state, queue and log adapter and the test run from a table (the status line still `1 building · 1
  merging · 1 testing · today $1.00`); "a table whose pid is dead draws nothing".
  Break: scripts/__tests__/run-shell-tests.test.sh -- a run's live table lists its files while they run and is gone when the run exits -- scripts/run-shell-tests.sh the live start line in run_one
  Break: scripts/__tests__/run-shell-tests.test.sh -- a skipped own-lane file finishes as skip in the live table, and under --own-lane the ordinary file it leaves out never enters it -- scripts/run-shell-tests.sh the live end skip line per skipped SEL file, and the EXCL file kept out of SEL
  Break: hooks/units.test.tsx -- a merge check's test lines show files done and the first failure in its merge row, and its tmp copy's table draws no test row -- hooks/units.tsx readTests' ownerOf skip of a worktree outside $PP_WORKSPACES
- Planning seats (revision 2, Decision G10-9). Host `seatState` (host `units.tsx:73-83`) reads `long-jobs/<seat>.rc`
  and `.lock`; the plugin's seats leave a record `$PP_SCRATCH/seat-<unit>-<role>.txt` (`seat.sh:435-436`: `role=`,
  `unit=`, `phase=launching`; `phase=dispatched` :571; `phase=failed` :573 on a failed launch; `verdict=` and
  `collected=` at collect, :692-693). The plugin's `seatState` reads the records whose names start with the prefix
  (`seat-<unit>-plan-author`, `seat-<unit>-plan-judge`) from one `$PP_SCRATCH` listing per poll (in place of the
  host's `long-jobs` listing in `collect`, host :181), each through the host's `parsed` cache (size and mtime): any
  record with a `verdict=` line is `done`; else a record whose last `phase=` is not `failed` is `running`; none is
  `null` (nothing drawn). `running` wins over `done`, as on the host. The host's `flock` call goes.
  Test: `hooks/units.test.tsx` "a planning unit shows its plan author done and its judges running from the seat
  records" (`${SCR}/seat-p-plan-author.txt` holding `phase=dispatched` and `verdict=PLAN-DONE`;
  `${SCR}/seat-p-plan-judge-sol.txt` holding `phase=dispatched` only: `Plan ✓  Judges ◐`); "a seat whose launch failed
  shows nothing for it" (`phase=failed`, no verdict: no `◐` for the judges).
  Break: hooks/units.test.tsx -- a seat whose launch failed shows nothing for it -- hooks/units.tsx seatState's phase=failed test
- Planning issues (revision 5, Decision G10-12). Host `closesOf` (host `sources.ts:216`) reads the plan's first
  `Closes:` line and keeps only `#<n>` tokens; the plugin's plans write `Closes: issue 348, issue 349` (this plan's
  line 6), so the unchanged port returns `[]` and a planning unit shows no issues. The port reads both forms and
  returns the host's `#<n>` strings, so `units.tsx`'s use (host :92) is unchanged: `export const closesOf = (plan:
  string): string[] => (/^Closes:\s*(.+)$/m.exec(plan)?.[1].match(/#\d+|\bissue\s+\d+/gi) ?? []).map(x =>
  `#${x.replace(/\D/g, '')}`)`. The comment above it becomes "A plan's `Closes: issue 1, issue 2` (or `Closes: #1
  #2`) line names the unit's issues before any Builder log does". A line such as `Closes (only when G19 is built):`
  is not `Closes:` and is not read, as on the host.
  Catches: a planning unit of a plugin plan drawn with no issues until a Builder log names them.
  Test: `hooks/units-sources.test.tsx` "a plan's Closes line names its issues in the plugin's form and the host's":
  `closesOf('Closes: issue 348, issue 349\n')` equals `['348', '349'].map(n => '#' + n)`; `closesOf('Closes: #12
  #34\n')` is `['#12', '#34']`; `closesOf('Closes: issue 348\nCloses (only when G19 is built): issue 366\n')` equals
  `['348'].map(n => '#' + n)`. The expected values are built, not written as a hash and three digits, because
  `ci/leak-words.txt:36` (`#[0-9]{3,4}\b`) fails any shipped file holding one. For the same reason the host case
  whose plan fixture is `Closes:` with two four-digit hash references (host `units.test.tsx:256`, its issue line at
  :276) is ported with `Closes: issue 12, issue 34\n`, the plugin's form, and expects `#12 #34` where the host
  expects its two numbers.
  Break: hooks/units-sources.test.tsx -- a plan's Closes line names its issues in the plugin's form and the host's -- hooks/units-sources.ts closesOf's issue <n> alternative
- Merge-state adapter (Decision G10-6). The host's `readMerges` (host `units.tsx:98-125`) finds merges by
  `long-jobs/merge-<unit>.lock` and `.rc`; the plugin has no `long-jobs` folder. What the plugin's merge leaves, read
  on `9ac91d3`:
  - `<git common dir>/merge-unit-local.state` (`merge-unit-local.sh:90-95`): `unit=`, `sha=`, `tip=`, `pid=`,
    `started=` (epoch seconds, `date +%s`, :196), `stage=`, `main=`, `log=`; written while a merge holds main and
    removed by `release` (:96-99) on every way out, so a refused merge leaves none and only a killed one leaves a
    file whose pid is dead (`paths.sh:488-491`, `merge-unit-local.sh:87-89`).
  - `<git common dir>/merge-unit-local.queue/<unit>@<sha>`: the pid of a request waiting on the lock (`paths.sh:490`).
  - `$PP_SCRATCH/merge-<unit>.log`, two writers (revision 4, CORRECTED): `pp_detach` (`merge-unit-local.sh:56`,
    `paths.sh:481-486`) truncates it at each detached start of a lone merge, but `merge-queue.sh`'s `queue`
    (:43-47) APPENDS each queued attempt's stdout and stderr (`>> "$log"`) and never empties it (issue 317), so one
    log can hold many attempts. Lines: `STEP <n> <name>: ...` (:235, :274), `FAILED <step>: <reason>` from `fail`
    (:79), `DONE unit=<unit> ...` at the end of a merged run (:635; a `--cleanup` run's at :186). A run in a
    foreground that is not main's writes no log.
  - The attempt marker (revision 4, a new producer line; it replaces every earlier "does the log hold DONE" reading).
    No existing line opens an attempt: a refusal at :80-:232 prints only `FAILED step 1 preconditions: ...`, with no
    `STEP 1` line before it, so no line on `9ac91d3` can split an appended log. G10 adds one line to
    `merge-unit-local.sh` after the unit-name check (:78) and before `fail` (:79): `[ "$DRY_RUN" = 1 ] || echo
    "ATTEMPT unit=$UNIT pid=$$ started=$(date +%s)"`. Only the process holding the lock reaches it (the first pass
    execs itself under `flock` at :62-64), so it prints once per attempt, after any wait on the lock, with the same
    `$$` the state's `pid=` records (:93). A duplicate request's exit 4 (:51) and a usage error (exit 2, :39,
    :74-78) come before it and open no attempt. An attempt in the log starts at a line matching `^ATTEMPT unit=<unit>
    ` (the unit compared as a literal string) and runs to the next such line or the end of the file; the newest
    attempt is the lines from the LAST such line to the end. The log's other readers are unaffected: `merge-queue.sh`
    reads `tail -n 1`/`tail -n 3` (:60, :52, :57), `pp_detach` sends `tail -n 5` (`paths.sh:485`), and the tests grep for a line
    (`merge-lock.test.sh:87`, `merge-unit-local.test.sh:166`, `merge-queue-train.test.sh:19`); none counts lines or
    reads the first line (`rg -n 'head -1|head -n 1|sed -n .?1p|wc -l' scripts/__tests__/merge-*.test.sh` matches only
    `merge-unit-local-cleanup.test.sh`'s own stub files, 2026-10-25). The host's `parseMergeLog` (host
    `sources.ts:33-48`) ignores a line it does not match, so it reads the marker as nothing.
  `loadPaths` (host :52-56) sources the plugin's own `scripts/paths.sh` (the plugin root is the mod's folder's
  parent, A7) with `cwd` main and prints `PP_MAIN`, `PP_SCRATCH`, `PP_WORKSPACES`, `${TMPDIR:-/tmp}`, `$HOME` and
  `git -C "$PP_MAIN" rev-parse --path-format=absolute --git-common-dir` as a new `gitDir` field of `Paths`.
  `readMerges` keeps the host's signature and return (`views`, `notes`, `ended`, `units`), so the rest of the mod
  and the host's `parseMergeLog` (host `sources.ts:33-48`, which already reads `STEP`, `FAILED` and `DONE unit=`)
  are unchanged. Its units are those named by a `merge-<unit>.log` in `$PP_SCRATCH` (`post-merge-*` does not match),
  by the state file's `unit=` and by a queue entry. Two sources decide the attempt, and neither ever reads an
  attempt older than the newest (revision 4, one design replacing revision 2's log-mtime test and revision 3's
  whole-log `DONE`/`FAILED` test):
  - The state, first. `release` (`merge-unit-local.sh:96-99`) removes it on every way out of the attempt that wrote
    it (its `pid=` is the remover's `$$`), a finished merge included, and the next attempt's `state` (:91-95)
    replaces the file. So a state naming the unit is the newest attempt that took the lock and wrote a state, live or
    killed, and while it is there the log is never read for that unit's outcome.
  - With no state for the unit, the log's newest attempt alone: `readMerges` hands `parseMergeLog` (host, unchanged)
    only the lines from the log's last `ATTEMPT unit=<unit> ` line to the end. A log with no such line (written
    before 0.48.0, or holding only a usage error) is no attempt: nothing is drawn from it (Accepted failure mode 9).
  Per unit, first match wins (`live <pid>` is `$.process.run(['kill', '-0', pid])` exiting 0; "recent" is the host's
  under 3,600 s, by the file's mtime; "the newest attempt" is the slice above):
  1. the state names the unit and its pid is live: `running`, its step the state's `stage=` (`preconditions`,
     `rebase`, `proof`, `merge`, `check`, `commit`, `post-merge`: :196, :273, :284, :466, :483, :516, :554),
     `elapsedSec` from `started=`; file counts from the newest attempt's `-- ok`/`-- FAIL` lines only when that
     attempt's `ATTEMPT` line has `pid=` equal to the state's `pid=`, else no counts (display only, Accepted failure
     mode 7);
  2. a queue entry `<unit>@*` holds a live pid: `running` (waiting on the lock, or in step 1 before its first
     `state`; no step yet);
  3. the state names the unit with a dead pid and it is recent: `stopped`, at its `stage=`; no toast (a dead state
     that is not recent is read as absent from here on: below, "no state names the unit" counts it as none);
  4. no state names the unit, the log is recent, and its newest attempt holds a `DONE unit=` line: `ended` (the
     host's `.rc` 0: the toast, no row);
  5. no state names the unit, the log is recent, and its newest attempt holds a `FAILED` line: `refused`, with its
     step and reason;
  6. no state names the unit, the log is recent, and its newest attempt holds neither (unfinished): `stopped`;
  7. otherwise nothing (no state, no live queue entry, and no log, a log over an hour old, or a log with no
     `ATTEMPT` line).
  Running comes first, unlike the host's `m.refused ? 'refused' : status` (host :124): a foreground rerun writes no
  log, so an earlier detached run's `FAILED` can outlive the run that is now live. Rule 3 before rules 4-5 covers the
  same gap once that rerun dies. Rules 4-6 read only the newest attempt, so an earlier attempt's `DONE` or `FAILED`,
  written in any second, never decides a later one's outcome, and two attempts in one second are still two slices.
  The band still lists `running` only (`fdb79064`, unchanged). No other mod code changes for the plugin shape beyond
  those named in this group.

  Every case, one table (revision 4; `ATTEMPT(p)` below is the line `ATTEMPT unit=u pid=<p> started=<s>`; every
  units.test.tsx merge fixture opens each attempt with such a line; a pid in the world's `live` set answers
  `kill -0`; clock 4,000,000 ms unless named):

  | case | state | queue | `${SCR}/merge-u.log` | expected | test (`hooks/units.test.tsx`) |
  |---|---|---|---|---|---|
  | no state, no log | none | none | none | nothing drawn, no toast | "a unit with no merge state, queue entry or log draws no merge row" (NEW) |
  | queued, no state | none | `u@abc` holding a live pid | none | `running`, no step | "a queued merge reads as running" |
  | state, live pid | `unit=u pid=8 stage=rebase started=3990` | none | `ATTEMPT(8)` / `STEP 2 rebase: y` | `running` at `rebase` in band and pane | "a live merge state names a running merge in the band and the pane" |
  | state, live pid, earlier refused log | `unit=u pid=9 stage=check` (a foreground rerun) | none | `ATTEMPT(8)` / `FAILED step 3 record: review ledger has no GO` | `running` at `check`, no file counts (the attempt's pid is not 9) | "a live rerun beside an earlier refused log reads as running" (its no-counts check added) |
  | state, dead pid, recent | `unit=u pid=8 stage=rebase`, mtime 10 s old | none | `ATTEMPT(8)` / `STEP 2 rebase: y` | `stopped` at `rebase` in pane and `/units`, nothing in the band, no toast | "a merge whose pid died shows stopped in the pane and /units, and nothing in the band" |
  | state, dead pid, same second as a DONE (same-second attempts) | `unit=u pid=8 started=200`, mtime 200,000 ms | none | `ATTEMPT(7)` / `DONE unit=u`, mtime 200,000 ms; clock 201,000 ms | `stopped`, no `merge finished` toast | "a dead merge state beside a DONE log of the same second reads stopped, with no merge finished toast" |
  | state, dead pid, over an hour old | `unit=u pid=8`, mtime 3,601 s old | none | `ATTEMPT(9)` / `FAILED step 1 preconditions: x`, 10 s old | `refused at step 1 preconditions: x` | "a dead merge state over an hour old draws nothing, and a recent refusal in the log then shows" |
  | log, one attempt, DONE | none | none | `ATTEMPT(7)` / `STEP 1 preconditions: y` / `DONE unit=u merged=local sha=abc` | `ended`: `merge finished` toast once, no row | "a merge whose log ends DONE toasts merge finished once and draws no row" |
  | log, one attempt, FAILED | none | none | `ATTEMPT(7)` / `STEP 1 preconditions: y` / `FAILED step 3 record: review ledger has no GO` | `refused at step 3 record: review ledger has no GO` in pane and `/units`, nothing in the band | "a refusal shows its step and reason in the pane and /units, and nothing in the band" |
  | log, one attempt, unfinished | none | none | `ATTEMPT(7)` / `STEP 2 rebase: y` | `stopped` at `2 rebase`, no toast | "a log whose newest attempt has no DONE or FAILED line reads stopped" (NEW) |
  | log, earlier DONE then later FAILED, same second | none | none | `ATTEMPT(7)` started=200 / `DONE unit=u` / `ATTEMPT(8)` started=200 / `STEP 1 preconditions: retry` / `FAILED step 3 record: review ledger has no GO` | `refused at step 3 record: review ledger has no GO`, no `merge finished` toast | "an earlier attempt's DONE in an appended log does not hide the newest attempt's refusal, in the same second or not" (NEW; the judge's fixture with markers) |
  | log, earlier DONE then later unfinished | none | none | `ATTEMPT(7)` / `DONE unit=u` / `ATTEMPT(8)` / `STEP 2 rebase: y` | `stopped` at `2 rebase`, no toast | "an earlier attempt's DONE followed by an unfinished attempt reads stopped, with no merge finished toast" (NEW) |
  | log, earlier FAILED then later DONE | none | none | `ATTEMPT(7)` / `FAILED step 1 preconditions: x` / `ATTEMPT(8)` / `DONE unit=u` | `ended`: one toast, no row | the same NEW case as the DONE-then-FAILED row, its second half |
  | log over an hour old | none | none | `ATTEMPT(7)` / `FAILED ...`, mtime 3,601 s old | nothing | "a refused log over an hour old draws nothing" |
  | log with no ATTEMPT line (before 0.48.0) | none | none | `STEP 1 preconditions: y` / `DONE unit=u`, 10 s old | nothing, no toast | "a log with no ATTEMPT line draws nothing and toasts nothing" (NEW) |

  The producer side: `scripts/__tests__/merge-queue.test.sh` (no time-bound check): "a unit queued twice appends one
  ATTEMPT line per attempt, the first attempt's step 1 refusal after its own" (the first request refused at step 1,
  `worktree does not exist`, the worktree then made, the second merged: the log holds two `ATTEMPT unit=<u>` lines,
  the `FAILED step 1 preconditions` line between them, the `DONE unit=` line after the second); its `pid=` equals the
  state's `pid=` while the second runs (read from the state at its `stage=` the way `merge-lock.test.sh:26` reads it).
  Break: scripts/__tests__/merge-queue.test.sh -- a unit queued twice appends one ATTEMPT line per attempt, the first attempt's step 1 refusal after its own -- scripts/merge-unit-local.sh the ATTEMPT echo placed after :78 and before the first fail call
  Break: hooks/units.test.tsx -- an earlier attempt's DONE in an appended log does not hide the newest attempt's refusal, in the same second or not -- hooks/units.tsx readMerges' slice from the log's last ATTEMPT line
  Break: hooks/units.test.tsx -- a log with no ATTEMPT line draws nothing and toasts nothing -- hooks/units.tsx readMerges' no-ATTEMPT-line branch
  Catches: a stopped or refused merge shown as running in the band, or a live merge missing because no `long-jobs`
  folder exists.
  Break: hooks/units.test.tsx -- a merge whose pid died shows stopped in the pane and /units, and nothing in the band -- hooks/units.tsx readMerges the live-pid test in rule 1
  Break: hooks/units.test.tsx -- a refusal shows its step and reason in the pane and /units, and nothing in the band -- hooks/units.tsx readMerges rule 5
  Tests (`hooks/units.test.tsx`; the host's merge cases, its fixtures moved from `${SCR}/long-jobs` to `${GITDIR}/merge-unit-local.state`,
  `${GITDIR}/merge-unit-local.queue/` and `${SCR}/merge-u.log`, the world's `live` set answering `kill -0`; no
  `long-jobs` folder in any merge case; every log fixture opens each attempt with an `ATTEMPT` line, revision 4):
  the fifteen cases of the table above, each with the fixture and expected result its row names, the merge cases in
  the table's order.
  Break: hooks/units.test.tsx -- a dead merge state beside a DONE log of the same second reads stopped, with no merge finished toast -- hooks/units.tsx readMerges' rule 3 (a dead state) placed before the log's DONE and FAILED rules
- Merge gate (the host's change), a block of its own in step 4 after the check (`merge-unit-local.sh`, after :512,
  before `state commit` :516), outside the `REUSED`/`CHECK_CMD` branches (:494-512), so it runs with no
  `testCommand` and when the closing pass's suite proof is reused: when the squash changes a path under
  `hooks/*.ts`, `hooks/*.tsx` or `types/` (`SQUASH_PATHS`, :465) AND the merged tree has `.claude-plugin/plugin.json`
  (`git cat-file -e "$TREE:.claude-plugin/plugin.json"`), it echoes `STEP 4 plugin: claude plugin validate . &&
  claude plugin test .`, makes its own copy of `$TREE` the way the check does (`COPY=$(mktemp -d)`, `git worktree add
  -q --detach "$COPY/tree" HEAD`, `read-tree -u --reset "$TREE"`, `pp_link_node_modules`), runs both commands there,
  and on red `fail "step 4 plugin" "claude plugin validate or test is red on the merged tree (output above); fix it in
  $WT and run another pass"` (the EXIT trap's `undo_squash` puts main back, as for a red check), then `drop_copy`.
  A reused suite proof does not cover it: the proof is the project's `testCommand`, which never loads the mod
  (Decision G10-5).
  Catches: a mod change that breaks the mod's own tests or the manifest, which the shell suites never load, merged
  because the project has no `testCommand` or because the closing pass's suite was reused.
  Break: scripts/__tests__/merge-unit-local.test.sh -- a plugin unit changing hooks/x.ts with no testCommand runs claude plugin validate and test on the merged tree -- scripts/merge-unit-local.sh the plugin block placed outside the CHECK_CMD branch
  Break: scripts/__tests__/merge-queue.test.sh -- a merge that reuses the closing pass's green suite still runs claude plugin test on a plugin unit -- scripts/merge-unit-local.sh the plugin block placed outside the REUSED branch
  Break: scripts/__tests__/merge-unit-local.test.sh -- a red claude plugin test refuses the merge and leaves main where it was -- scripts/merge-unit-local.sh the fail "step 4 plugin" call
  Tests: a `claude` stub in the fixture's `$TMP/bin` (`fixtures/merge-unit-local-setup.sh:23-39`; `merge-queue-setup.sh:4`
  sources that file) logs its arguments and `pwd` to `$TMP/claude-calls` and exits 1 while `$TMP/claude-red`
  exists. `merge-unit-local.test.sh` (after its timed cases): "a plugin unit changing hooks/x.ts with no testCommand
  runs claude plugin validate and test on the merged tree" (both calls logged, their `pwd` the copy, not main);
  "a red claude plugin test refuses the merge and leaves main where it was" (exit 1, `FAILED step 4 plugin`, main's
  HEAD unchanged, no squash left staged); the existing "not a plugin" case below. `merge-queue.test.sh` (its reuse
  fixture, :12-15): "a merge that reuses the closing pass's green suite still runs claude plugin test on a plugin
  unit" (the `reused, not run again` line and both `claude` calls).

### G11 -- releases: issue 348

- `scripts/release-notes.sh <version>`: prints that version's CHANGELOG section, the text `update.sh:27` prints for
  the newest (`update.sh` calls it). Exit 1 with a message when the section is missing.
- `scripts/release-decide.sh <before sha> <after sha>`: the one decision path. Prints `release v<version>` when
  `.claude-plugin/plugin.json`'s version at `<after>` differs from `<before>`'s and tag `v<version>` or its GitHub
  release (`gh release view`) does not exist, so a run that pushed the tag and then failed to publish is finished by
  the next (pass 1); otherwise `skip: <why>`. Exit 0 either way; exit 1 when a version cannot be read, and the
  Decide step fails with it (the decision is assigned first, then written). The Tag step skips a tag that exists.
- `.github/workflows/release.yml`, on push to `main` (`contents: write`, its own job; `ci.yml` keeps `contents:
  read`): its first step runs `bash scripts/release-decide.sh "${{ github.event.before }}" "$GITHUB_SHA"`, and every
  later step runs only when that output starts `release `. It then tags `v<version>` and publishes the release with
  `release-notes.sh`'s notes; a release that exists already changes nothing; a missing section fails the job.
  Catches: a push that would tag or publish a version already released, or one whose version did not change.
  Break: scripts/__tests__/release-notes.test.sh -- an unchanged version decides skip -- scripts/release-decide.sh the version compare
  Break: scripts/__tests__/release-notes.test.sh -- the release workflow gates every tag and publish step on release-decide's output -- .github/workflows/release.yml the if: on each later step
- `scripts/release-backfill.sh [--plan]`: for each version, oldest first, the commit that set it in `plugin.json`
  (`git log -S`), tag and release unless they exist. `--plan` prints and does nothing.
- Nothing in this unit runs the backfill, tags, publishes or writes release notes (the owner's order: no release
  notes, README or backfill until all plugin work is merged; Decision G11-1). The workflow fires on a push, and this
  merge is local.

### G12 -- the rule drift items RD1-RD13 (section "Rule drift items")

Copied whole, sites re-read; one item dropped (RD8, already in place). Built after G9.

### G15 -- the reviewer's `Class search:` FORMAT line (host `55126a9c`, the missing part)

Already on main from part A1's G14 (evidence): `class_sites` runs each `Class search: rg ...` line as rg with no
shell (`builder-codex-pass.sh:882-939`); the Sites gate refuses the next pass while a hit is missing
(:952-958); the call after the round file (:1368-1369); the fix brief's `## Class sites` section (:1440); the
template's sentence (`templates/_builder-brief-template.md:199-200`); rg in the requirements (`docs/requirements.md:10`) and
the pass's no-rg refusal (`builder-codex-pass.sh:774`); `scripts/__tests__/builder-codex-pass-class-sites.test.sh`. Missing: the host's `FORMAT` sentence that asks
the reviewer to write the line, so today a reviewer writes one only if it guesses. `FORMAT` (:103) gains, after the
class-tag sentence: "Under each blocking finding write one line, Class search: rg <arguments>, a read-only rg search
run from the repository root whose hits are every place with the same mistake, the <file>:<line> of that finding
among them; the author must answer for each hit. A known gap carries no Class search line." The plugin's class tag and
KNOWN GAPS rule stay (Decision G15-1). Not ported: the host's main-card trim and its rule-file lines (the plugin's
rule is the template sentence above, already there) and the host test's background-run wording (RD13 covers it).

### G16 -- design-only passes (host `95730a8d`)

- `builder-codex-pass.sh`: `HEAD_DESIGN` beside `HEAD_FULL`/`HEAD_FIX`/`HEAD_FINAL` (:152-154), the host's text
  (no apostrophe). `session_proof` (:194) and `pass_threads` (:423) pass it as a fourth head; `session_proof`'s
  `heads` map (:312) gains `design`. `--verify` (:569-577) gains `design) die "<round> is a design-only pass (its
  commit changed only the plan): its GO approves the design and merges nothing. Write the code, then run
  builder-codex-pass.sh <unit> <N+1> final"`.
  Catches: a design-only GO merged as if the code had been reviewed.
  Break: scripts/__tests__/builder-codex-pass-closing.test.sh -- its GO merges nothing -- scripts/builder-codex-pass.sh --verify the design) case
- `plan_only <commit>`: true when the commit changes nothing outside `.claude/plans/`, `.claude/briefs/`,
  `.claude/metrics/`; it replaces the plans-only test at :964 (so the after-design New code check uses it too).
- `PRE=$(git -C "$WT" rev-parse HEAD)` before the pass commit (:1066). CORRECTED (revision 2): on `9ac91d3` the
  script first sets `SHA` at :1068, after `rebase_and_test` (:1067), where the host sets it before (host `95730a8d`:
  `SHA=` right after the commit, the `DESIGN` line, `rebase_and_test`, then `SHA=` again). So after the commit and
  before `rebase_and_test`, three lines in this order: `SHA=$(git -C "$WT" rev-parse HEAD)` (the pass commit's own
  tip), a comment that the check reads that tip before the rebase moves it, and `DESIGN=; [ "$KIND" != final ] || [
  "$SHA" = "$PRE" ] || ! plan_only "$SHA" || DESIGN=design`. The existing `SHA=` at :1068 stays and refreshes `SHA`
  to the rebased tip, which the suite, the review input and the round file read as today. Under `set -euo pipefail`
  (:68) a `SHA` read before it is set ends the pass, and an inherited `SHA` would judge the wrong commit; reading
  HEAD first rules out both. `HEAD_LINE` (:1121)
  is `HEAD_DESIGN` when `DESIGN` is set. The round file's `Pass:` line (:1361) prints `${DESIGN:-$KIND}`. After the
  NARROWED GO line (:1366): `DESIGN GO: this GO approves the design and merges nothing. Next: write the code, then
  builder-codex-pass.sh <u> <N+1> final; print your DONE line only after that pass's GO.`
  Break: scripts/__tests__/builder-codex-pass-closing.test.sh -- a final whose commit changes only the plan reads under the design head, says so, and its round file says design -- scripts/builder-codex-pass.sh the DESIGN set after the commit
  Test (revision 2): the same file, beside that case, "a design-only final reads its own commit before the rebase:
  run with SHA unset after a recorded first pass and a plan-only commit, it reads as design; run with SHA set to a
  code commit, it still reads as design" (`env -u SHA bash scripts/builder-codex-pass.sh u 2 final` on the fixture,
  then the same with `SHA=<the first pass's code commit>`: each exits 0 with `Pass: design` and the review input
  under `HEAD_DESIGN`).
  Break: scripts/__tests__/builder-codex-pass-closing.test.sh -- a design-only final reads its own commit before the rebase -- scripts/builder-codex-pass.sh the SHA read placed before the DESIGN line
- The class-stop fix brief text (:1448, "run the next pass (final) on that design alone") gains the host's
  parenthesis right after "on that design alone", as host `95730a8d` places it: "(a commit with no code runs as a
  design-only pass: its reviewer judges the design, and its GO merges nothing)". That splits the phrase
  `scripts/__tests__/builder-codex-pass-class-return.test.sh:35` matches, so its grep becomes `...run the next pass
  (final) on that design alone (a commit with no code runs as a design-only pass: its reviewer judges the design, and
  its GO merges nothing) and fix the design until a pass is GO` (the host updated its own test the same way); the
  check keeps its name "the redesign comes in order: data design and failure table first, a design-only pass to GO,
  then the code, then a whole-branch pass".
- `main-watch.sh`, the narrowed and design wordings kept apart as host `95730a8d` keeps them (two `case` arms in
  `auto_merge`'s note): `report_wake` (:928-934) gains `design:GO) next="design only, merges nothing -- the Builder
  writes the code, then builder-codex-pass.sh $2 $((n + 1)) final"` beside the unchanged `review:GO` arm.
  `report_notes` (:1268) becomes a `case "$line"`: `"GO (review)"` keeps today's `NARROWED="Finished on a narrowed
  pass; needs a final pass: builder-codex-pass.sh $2 $((NR_N + 1)) final."` and sets `GO_PASS=narrowed`; `"GO
  (design)"` sets `NARROWED="Finished on a design-only pass; the code is not reviewed yet: builder-codex-pass.sh $2
  $((NR_N + 1)) final."` (the host's text) and `GO_PASS=design-only`; both cleared with `NEWEST`. The finish subject
  at :1250 reads `finished on a $GO_PASS pass; needs a final pass`, so a narrowed GO's subject is today's text
  unchanged. `NARROWED` keeps its name (its readers :1231, :1248, :1251 are unchanged); the comment at :1260 names
  both kinds.
  Test: `main-watch-report-wake.test.sh`'s narrowed case (:47-55: `Pass: review`, `VERDICT: GO`, then DONE) stays
  unchanged and green, still asserting `Finished on a narrowed pass; needs a final pass: builder-codex-pass.sh rn 2
  final`; a new case after it, "a DONE after a design GO is posted as finished on a design-only pass, not as narrowed,
  and is not merged" (`rnd rd 1 design GO`, DONE: one post of `Finished on a design-only pass; the code is not
  reviewed yet: builder-codex-pass.sh rd 2 final`, none of `Finished on a narrowed pass`, no `rd@` in `mq-calls`).
  Break: scripts/__tests__/main-watch-report-wake.test.sh -- a DONE after a design GO is posted as finished on a design-only pass, not as narrowed, and is not merged -- scripts/main-watch.sh report_notes the "GO (design)" arm

### G17 -- the prompt cache per role (item 3, BUILT, the cache issue)

Facts (the owner's measurements, 2026-10-25): F-a, a worktree also reads the main checkout's
`.claude/settings.local.json`, and on a conflict the main checkout's value wins; F-b, an inherited process env var
loses to `env` in the user settings, so a launch-time env var does not set a TTL; F-c, a `--settings <file>` launch
flag beats both, and only that process reads it.

Today: `promptCacheTtl` (`5m|leave`, main and workers) writes `promptCacheTtl`/`subagentPromptCacheTtl` "5m" into
the shared `.claude/settings.json` (`setup.sh:414-415`, `il_cache_ttl`, `install-lib.sh:271-289`) and
`CLAUDE_CODE_PROMPT_CACHE_TTL=5m` into each worker worktree's `settings.local.json` (`worktree-setup.sh:166-170`);
`relayPromptCacheTtl` (`1h|leave`) writes 1h into the Chief-of-Staff worktree's `settings.local.json`
(`worktree-setup.sh:100-102`, the relay branch, which exits at :110 before the worker branch). Main has a file only
it reads: `.claude/main-session.settings.json` (`IL_MAIN_LEAN_FILE`, `install-lib.sh:498`, gitignored, read only by
`claude --settings <it>`; setup's note `setup.sh:505` says start main that way). Main's restart replays that flag:
`hooks/context-clear-stop.sh:173-180` rebuilds the parent command, and a plain path passes its character check.

Change:
- Options (`.claude-plugin/plugin.json:240-253`): `relayPromptCacheTtl` (title "Chief of Staff prompt cache", options
  `5m|1h|leave`, default `1h`), new `mainPromptCacheTtl` ("Main prompt cache", `5m|1h|leave`, default `1h`), new
  `workerPromptCacheTtl` ("Builder and worker prompt cache", `5m|1h|leave`, default `5m`; its description says
  subagents follow it). `promptCacheTtl` is removed (Decision G17-1).
- `scripts/paths.sh:1146`: `mainPromptCacheTtl) p=.mainCacheTtl`, `workerPromptCacheTtl) p=.workerCacheTtl`,
  `relayPromptCacheTtl) p=.chiefOfStaff.cacheTtl` (unchanged); `promptCacheTtl` goes. No pp_option default (as today:
  an unanswered role writes nothing and setup lists it under Needs you).
- `scripts/setup.sh`: flags `--main-cache-ttl`, `--worker-cache-ttl`, `--relay-cache-ttl`, each `5m|1h|leave`
  (:213-214, `TAKES` :55, usage :12, comment :37-39); `--cache-ttl` goes (one `config/retired.tsv` row lints it,
  replaced by the two new flags). Carry-over :119 reads `.mainCacheTtl`, `.workerCacheTtl`, `.chiefOfStaff.cacheTtl`.
  The config writer (:394, :399) and the options writer (:478) carry the three. :414-415: `il_cache_ttl` now writes
  only `subagentPromptCacheTtl`, with the worker answer when it is 5m or 1h (Decision G17-3); leave does not call it,
  as today, so a value an earlier setup wrote stays. Needs you (:493, :495): one line per unanswered role, each
  opening with its question's title (revision 4, so the update skill can match it): `Main prompt cache: not answered
  since 0.48.0; /commandeck:setup asks, or: setup.sh --main-cache-ttl 5m|1h|leave`, `Builder and worker prompt cache:
  ... --worker-cache-ttl 5m|1h|leave`, and, when a relay is named (:495's guard), `Chief of Staff prompt cache: ...
  --relay-cache-ttl 5m|1h|leave`. The summary line (:629) prints `prompt cache: main <v>, workers <v>, relay <v>`
  (the answer per role, `leave` or `not answered` included).
- The update skill (revision 4; `skills/update/SKILL.md:29`, the consumer of those Needs-you lines): "If update shows
  a `Main prompt cache:`, `Builder and worker prompt cache:` or `Chief of Staff prompt cache:` line under Needs you,
  ask that question from `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` word for word, then run `bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh` with only that question's flag: `--main-cache-ttl`, `--worker-cache-ttl` or
  `--relay-cache-ttl`. Never run setup.sh without the answer." `scripts/update.sh:69` prints setup's Needs-you block
  as it is (no change). Test: plugin.test.sh :203, renamed "the update skill asks each role's prompt cache question
  from setup's text, with only that question's flag", greps `skills/update/SKILL.md` for `Main prompt cache:.*Builder
  and worker prompt cache:.*Chief of Staff prompt cache:` and for each of the three flags (expected `1:1:1:1`); and a
  new plugin.test.sh check, "each Needs-you prompt cache line opens with its setup question's title and names its
  flag" (`grep -c` in `scripts/setup.sh` for `NEED+=("Main prompt cache: not answered since 0.48.0` with
  `--main-cache-ttl`, and the same for the other two; expected `1:1:1`), so a renamed question or line fails here.
  Break: scripts/__tests__/plugin.test.sh -- each Needs-you prompt cache line opens with its setup question's title and names its flag -- scripts/setup.sh the three NEED+= lines at :493-495
- Main's value (Decision G17-2): `il_main_lean` (`install-lib.sh:503`) takes the main answer: when it is 5m or 1h,
  its wanted keys are `IL_MAIN_LEAN` plus `{"env": {"CLAUDE_CODE_PROMPT_CACHE_TTL": <answer>}}`, written key by key
  into `.claude/main-session.settings.json` with its existing ownership rule (`mainLean` in the manifest: a key the
  owner holds stays and is named; a rerun replaces only setup's own value; uninstall's `off` takes out what setup
  wrote). Leave writes nothing (issue 367; revision 4, CORRECTED: revision 3 had leave take out setup's earlier
  value, which `il_main_lean` would do by itself, since a recorded key missing from the wanted keys falls in
  `$mine - $take` and is deleted, `install-lib.sh:510-513`). So on leave the wanted keys are `IL_MAIN_LEAN` plus
  setup's own recorded TTL, `{"env": {"CLAUDE_CODE_PROMPT_CACHE_TTL": <the record's value>}}`, added only when the
  record (`.entries[<file>].mainLean.env.CLAUDE_CODE_PROMPT_CACHE_TTL`) has one AND the file still holds that value:
  the key stays byte for byte and so does its record, so uninstall still takes it out. No record, or a value the
  owner changed since: nothing is added for the TTL, and the owner's key is the owner's (no note, as for any other
  key the owner changed). `il_main_lean <manifest> <file> [off|<main answer>]`: setup passes the main answer
  (`setup.sh:485`, `"$MCACHE_ON"`); an unanswered main passes `leave` (it writes nothing either, and Needs you asks).
  The call on main's `settings.local.json` with `off` (:484) stays. Nothing writes a TTL into the main checkout's
  `settings.local.json` or into `.claude/settings.json`.
  Break: scripts/__tests__/install-lib-setup.test.sh -- setup writes main's TTL only into main-session.settings.json -- scripts/install-lib.sh il_main_lean the env key added for a 5m or 1h answer
  Break: scripts/__tests__/install-lib-setup.test.sh -- a /config answer of leave keeps the 1h setup wrote, and its record, a flag does not beat /config, and a /config 5m then replaces it -- scripts/install-lib.sh il_main_lean the leave branch adding setup's recorded TTL to the wanted keys
  Test (revision 4, replacing revision 3's "a rerun answered leave takes out only the TTL setup wrote, and 5m writes
  it again"; revision 5 keeps the `/config` precedence of `il_plugin_options`, `install-lib.sh:459-466`, and changes
  the `/config` answer in the replay, since setup's first run prefills `/config` and a later flag never replaces it):
  install-lib-setup.test.sh "a /config answer of leave keeps the 1h setup wrote, and its record, a flag does not beat
  /config, and a /config 5m then replaces it". "TTL" below is `.env.CLAUDE_CODE_PROMPT_CACHE_TTL` in
  `.claude/main-session.settings.json`, "record" the manifest's `mainLean.env.CLAUDE_CODE_PROMPT_CACHE_TTL`, and
  "/config" `.pluginConfigs[<plugin key>].options.mainPromptCacheTtl` in the fixture's user settings (the path
  `il_plugin_options` writes), which the test edits with `jq` as the owner's /config would. Fixture: configured, with
  no `mainPromptCacheTtl` in /config.
  1. `setup.sh --main-cache-ttl 1h`: /config `"1h"` (prefilled); TTL `"1h"`; record `"1h"`.
  2. /config set to `"leave"`; `setup.sh --main-cache-ttl leave`: TTL `"1h"`; record `"1h"`.
  3. /config still `"leave"`; `setup.sh --main-cache-ttl 5m`: TTL `"1h"`; record `"1h"`; output holds `note:
     mainPromptCacheTtl is leave in /config, which beats this answer (5m)` (precedence kept).
  4. /config set to `"5m"`; `setup.sh --main-cache-ttl 5m`: TTL `"5m"`; record `"5m"`.
  5. uninstall's `il_main_lean ... off`: no TTL key; no record.
  And "a leave answer leaves an owner-changed TTL and drops setup's record" (setup `--main-cache-ttl 1h` wrote 1h and
  prefilled /config; the file then edited to 5m by hand and /config set to `"leave"`; `setup.sh --main-cache-ttl
  leave`: TTL `"5m"`, record with no TTL, no `note:` line).
- Worker and relay values: `worktree-setup.sh:166-170` reads `workerPromptCacheTtl` and writes `.env.CLAUDE_CODE_PROMPT_CACHE_TTL
  = $ttl` when it is 5m or 1h; :100-102 reads `relayPromptCacheTtl` and does the same for 5m or 1h. Leave writes
  nothing (as today).
  Break: scripts/__tests__/worktree-setup.test.sh -- each role's worktree gets its own TTL: a Builder 5m, the relay 1h, a Builder answered 1h gets 1h -- scripts/worktree-setup.sh:~170 the worker ttl test
  The relay's line (revision 3): today's `(if $rttl == "1h" then .env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h" else . end)`
  (:102) becomes `(if $rttl == "5m" or $rttl == "1h" then .env.CLAUDE_CODE_PROMPT_CACHE_TTL = $rttl else . end)`,
  set by path so the file's other `env` keys stay. Test: worktree-setup.test.sh, after the leave case (:37-39), "a
  relay answered 5m gets 5m, from a fresh settings file and beside another env entry" (`relayPromptCacheTtl=5m`;
  the Chief-of-Staff worktree's `settings.local.json` first `{}`, run: `.env.CLAUDE_CODE_PROMPT_CACHE_TTL` is `"5m"`;
  then `{"env":{"OTHER":"x"}}`, run: `.env` is `{"OTHER":"x","CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}`).
  Break: scripts/__tests__/worktree-setup.test.sh -- a relay answered 5m gets 5m, from a fresh settings file and beside another env entry -- scripts/worktree-setup.sh:~102 the relay's $rttl test taking 5m as well as 1h
- Doctor and setup report (`il_cache_ttl_report`, `install-lib.sh:396-430`, read by `doctor.sh:162` and
  `setup.sh:634`): one line per role (Decision G17-5):
  - main: `ok prompt cache: main <v> (.claude/main-session.settings.json; read only by a main started with claude
    --settings <that file>)`, or `warn` when that file's TTL is not the answer (the owner's key: change or remove it);
  - workers: `ok prompt cache: workers <v> (each worktree's .claude/settings.local.json; subagents:
    subagentPromptCacheTtl in .claude/settings.json)`, or `warn` naming the file whose value differs;
  - relay: today's chain check (:422-426) with the answer in place of the fixed 1h;
  - a role answered `leave`: `ok prompt cache: <main|workers|relay> leave (setup sets none)` (today's single line
    `ok prompt cache: setup sets none`, `doctor-options.test.sh:18`, becomes one per role).
  A TTL in the main checkout's `settings.local.json` stays `il_shadow_report`'s warning (:382-383, unchanged); its
  advice "move the key to ~/.claude/settings.json" stays right (each role's own value beats the user file, F-b, F-c).
- `hooks/no-poll-loops.sh:235-238`: no change. It reads the pane's own `CLAUDE_CODE_PROMPT_CACHE_TTL` (540 s at 1h,
  else 270 s) and limits worker panes only (`WORKER=1` in a linked worktree, :33-34): a Builder reads its worktree's
  value, the relay its own worktree's, and main (the main checkout, `WORKER=0`) is not limited by this rule. The
  comment at :235 names the per-role files. Test: Decision G17-4.
- Text: `skills/setup/SKILL.md:198-205` becomes three questions, each `Ask "<role> prompt cache": <default>
  (recommended) | <other> | Leave as is`; the 2026-10-18 figure that a 5-minute cache cost main 5% less goes (the
  owner's default for main is now 1h; Decision G17-6). `install-lib.sh:271-274` comment, `docs/setup-questions.md:24`,
  `docs/configuration.md:57` (`cacheTtl` -> `mainCacheTtl`, `workerCacheTtl`), `README.md:258-259` (the option rows)
  follow. The three questions, word for word (revision 4, so the tests below pin them; the titles are the options'
  titles):
  `    Ask "Main prompt cache": 1h (recommended) | 5m | Leave as is`,
  `    Ask "Builder and worker prompt cache": 5m (recommended) | 1h | Leave as is`,
  `    Ask "Chief of Staff prompt cache": 1h (recommended) | 5m | Leave as is`; under each, one bullet per answer
  ending with its flag (`--main-cache-ttl 1h` ...), each Leave as is bullet reading `- Leave as is: writes nothing;
  what is set now stays, a value an earlier setup wrote included. `--<role>-cache-ttl leave`` (`main`, `worker`,
  `relay`). The relay's 1h bullet keeps its 85% figure (measured on the relay, not main).
- The cache-text consumers in `scripts/__tests__/plugin.test.sh` (revision 4; `rg` of the option names and question
  text over `scripts`, `skills`, `docs`, below):
  - :68-69 (the option-default table at :53-75, each row one check "option <k> defaults to setup's recommended answer
    (<a>)", which greps `<a> (recommended)` in the setup text): the two rows
    become three, `mainPromptCacheTtl|"1h"|Ask "Main prompt cache": 1h`, `workerPromptCacheTtl|"5m"|Ask "Builder and
    worker prompt cache": 5m`, `relayPromptCacheTtl|"1h"|Ask "Chief of Staff prompt cache": 1h` (Decision G17-1's test).
  - :198 and :199 (the old two-choice questions and the main 5% text) are replaced by three checks, each `1:1:1` on
    the question line (`grep -cxF`), its default bullet's flag and its Leave as is bullet: "the main prompt cache
    question recommends 1h, offers 5m, and Leave as is writes nothing"; "the Builder and worker prompt cache question
    recommends 5m, offers 1h, and Leave as is writes nothing"; "the Chief of Staff prompt cache question recommends
    1h, offers 5m, and Leave as is writes nothing"; and one more, "no setup text says a 5-minute cache cost main less"
    (`grep -c 'about 5% less for main' "$SETUP"` is 0).
  - :203: as in the update-skill bullet above.
  Run: `bash scripts/run-shell-tests.sh scripts/__tests__/plugin.test.sh` (no time-bound check in it).
- The other consumers, every hit of `rg -n 'cacheTtl|cache-ttl|CacheTtl|Prompt cache|prompt-cache|prompt cache|5-minute'
  scripts hooks skills docs templates config README.md` (2026-10-25, revision 4) not named elsewhere in G17:
  - `scripts/__tests__/worktree-setup.test.sh:31` and `:36`: the fixtures write `"cacheTtl": "5m"` and `"leave"`,
    which G17 makes a key nothing reads, so "a worker and a Builder both get 5m" and "Leave as is writes no TTL
    anywhere" would fail: both become `"workerCacheTtl"` (the relay's `chiefOfStaff.cacheTtl` stays). Test: those two
    cases green with their names unchanged.
  - `scripts/__tests__/plugin-option.test.sh:71-72` and `:78-84`: `promptCacheTtl` -> `workerPromptCacheTtl` in
    `conf` and `O`, `cacheTtl` -> `workerCacheTtl` in the `jq` edit; the case names stay ("a /config 'leave' is an
    answer, though the project saved 5m"; "a worker pane follows /config's leave over the project's 5m"; "and the
    project's 5m with no /config answer").
  - `scripts/__tests__/doctor-run.test.sh:37`: its fixture ("as doctor-options.test.sh leaves it") follows
    doctor-options' new fixture, `"mainCacheTtl": "1h", "workerCacheTtl": "5m"` in place of `"cacheTtl": "5m"`; its
    one check (main's settings file against the orchestrator key) is unchanged; edited in place before its
    `timeout 60` call, no fixture added.
  - `hooks/__tests__/dependency-addition-guard.test.sh:130`, `:134`, `:151`: `--cache-ttl 5m` inside hook payloads
    (the guard exempts the plugin's own setup.sh by path, `dependency-addition-guard.sh:88-98`, and never runs it)
    becomes `--worker-cache-ttl 5m`, so no test names a removed flag; the three cases' results are unchanged.
  - `README.md:118` (the setup-questions row "Prompt cache, Relay prompt cache"): becomes "Main prompt cache, Builder
    and worker prompt cache, Chief of Staff prompt cache | 1 hour for main, 5 minutes for Builders and other worker
    panes, 1 hour for the relay pane; each 5m, 1h or left as is" (Decision V-1's list gains :118).
  - `docs/cost-control.md:14-16`: see the cache-checker bullet below.
  - `scripts/worktree-setup.sh:99` (comment "1h is written") -> "5m or 1h is written"; `:233` (comment "follows the
    setup answer like every worker's (owner, 2026-10-18") -> "follows the Builder and worker answer"; comments only.
  - Unchanged, read and left: `scripts/install-lib.sh:383` (`il_shadow_report`'s warning, still true: the main
    checkout's local file overrides every worktree); `docs/install.md:46` ("prompt cache settings", no option named);
    `hooks/no-poll-loops.sh:19`, `:366-374`, `hooks/worker-ask-guard.sh:44`, `scripts/wait-test-run.sh:4` (wait
    limits under the cache's life, which the pane's TTL already sets, Decision G17-4); `templates/_builder-brief-template.md:71`,
    `scripts/paths.sh:162`, `scripts/read-verdict.sh:820`, `scripts/seat.sh:820`, `hook-probe.test.sh`,
    `builder-fresh-round.test.sh:148`, `dashboard-collector-incremental.test.mjs:183`, `fixtures/doctor-setup.sh:35`
    (the word "prompt cache" or "five-minute" in another sense, no option or TTL value).
- The cache checker (`scripts/builder-cache-check.sh`; Decision G17-8): today :27 and :28 fail any main thread or
  subagent that wrote 1h cache, so a Builder answered `workerPromptCacheTtl=1h` fails its own proof. After
  `. paths.sh` (:12, which resolves the CALLER's project from the current folder, revision 4) it reads the answer of
  the worktree's own project, the way `worktree-setup.sh:84` and `:166` do: `P=$(git -C "$WT" rev-parse
  --path-format=absolute --git-common-dir 2>/dev/null) && P=${P%/.git} || P=$PP_MAIN`, then `WANT=$(PP_MAIN=$P
  pp_option workerPromptCacheTtl)` (a `$WT` that is no git checkout falls back to the caller's project, as today's
  whole check does; /config answers are the profile's and apply to both; subagents follow the worker answer through
  `subagentPromptCacheTtl`, Decision G17-3): `leave` prints `workers' prompt cache: leave (setup sets no TTL);
  nothing to prove` and exits 0 before reading a transcript; an unanswered key reads as `5m`, the option's manifest
  default and today's rule; `5m` or `1h` is the TTL each side must write. :27-28 become one rule per side: the wanted
  TTL's sum is over 0 and the other's is 0, else `FAIL: the main thread must write only $WANT cache (1h=$MH 5m=$MM)`
  (subagents the same). The header (:2-8) says it proves the worker answer, and the no-subagent message (:18) says
  "the $WANT side". Its one caller in tests is `scripts/__tests__/transcript-requests.test.sh:138-148` (no
  `timeout`); `proof-run.sh:124` and `worktree-setup.sh:235` name it and need no change. `docs/cost-control.md:14-16`
  (revision 4, CORRECTED: revision 3 called it unchanged, but it says the check fails unless both sides wrote only
  5-minute cache) becomes: "The cache check. `scripts/builder-cache-check.sh` reads a Builder's transcripts and fails
  unless its main thread and its subagents wrote only the prompt cache of the Builder and worker answer of the
  Builder's own project (5m or 1h; unanswered reads as 5m); with Leave as is it proves nothing and says so." Test:
  Claim 12's `rg`, widened to `docs` and to the words "5-minute prompt cache" and "5-minute cache".
  Tests (transcript-requests.test.sh, after :148, `$T/home-rv/.claude/settings.json` holding
  `{"pluginConfigs": {"commandeck@commandeck": {"options": {"workerPromptCacheTtl": "1h"}}}}`): "with
  workerPromptCacheTtl=1h a Builder and its subagents writing only 1h cache pass the check" (main and subagent
  transcripts holding only `ephemeral_1h_input_tokens`; `bash scripts/builder-cache-check.sh "$T/builder" s` exits 0);
  "with workerPromptCacheTtl=1h a main thread writing 5m cache fails the check"; "with workerPromptCacheTtl=leave the
  check proves nothing and exits 0 saying so". The existing "fails a Builder whose main thread wrote 1h cache"
  (no answer, so 5m) stays green. Revision 4, the per-project read (the judge's failing command): "the check proves
  the worktree's own project's answer, not the caller's" (no /config answer in `$T/home-rv`; project A, `$T/pa`, a
  git checkout whose `.claude/commandeck.json` holds `"workerCacheTtl": "5m"`; project B, `$T/pb`, with
  `"workerCacheTtl": "1h"` and a linked worktree `$T/pb-wt` (`git -C "$T/pb" worktree add`); `plog`'s transcripts for
  `pb-wt` hold only `ephemeral_1h_input_tokens` on both sides; `(cd "$T/pa" && HOME=$T/home-rv bash
  "$ROOT/scripts/builder-cache-check.sh" "$T/pb-wt" s)` exits 0, where reading A's answer would fail it on 5m).
  Break: scripts/__tests__/transcript-requests.test.sh -- with workerPromptCacheTtl=1h a main thread writing 5m cache fails the check -- scripts/builder-cache-check.sh the per-side compare against $WANT
  Break: scripts/__tests__/transcript-requests.test.sh -- the check proves the worktree's own project's answer, not the caller's -- scripts/builder-cache-check.sh the PP_MAIN=$P on the pp_option read
- `scripts/__tests__/doctor-options.test.sh` (G17's consumer of the option and report lines): the fixture at :11
  writes `"mainCacheTtl": "1h", "workerCacheTtl": "5m"` in place of `"cacheTtl": "5m"` (the relay part stays). The
  check at :14-15 keeps its name and greps `^ok option workerPromptCacheTtl: 5m (from $PROJ/.claude/commandeck.json)$`
  and `^ok option mainPromptCacheTtl: 1h (from $PROJ/.claude/commandeck.json)$` in place of the `promptCacheTtl` line
  (expected `1:1:1:1`). :17 sets `mainPromptCacheTtl`, `workerPromptCacheTtl` and `relayPromptCacheTtl` to `leave`;
  :18 becomes "the cache report follows the /config answers over the project's: one leave line per role", expecting 3
  lines matching `^ok prompt cache: (main|workers|relay) leave \(setup sets none\)$` (`grep -cE`); a role answered
  `leave` prints that line in `il_cache_ttl_report` (Decision G17-5). The option count check (:16) follows the
  manifest unchanged. Run: `bash scripts/run-shell-tests.sh scripts/__tests__/doctor-options.test.sh`.
- The legacy cache tests (revision 2, Decision G17-9): rewritten around the three-role contract, none kept for the
  removed behaviour. Run: `bash scripts/run-shell-tests.sh scripts/__tests__/install-lib.test.sh
  scripts/__tests__/doctor.test.sh scripts/__tests__/plugin-option.test.sh`.
  - `scripts/__tests__/install-lib.test.sh:195-206` (`il_cache_ttl` on a shared `promptCacheTtl`): the fixtures
    hold `subagentPromptCacheTtl` only and pass the worker answer. "an update moves the 1h an earlier setup wrote to
    the worker answer 5m, in the file and in the record" (`subagentPromptCacheTtl` and its record entry 5m); "a 1h the
    owner set (no record) stays 1h"; "taking setup's keys out leaves the owner's own 1h"; new "il_cache_ttl never
    writes promptCacheTtl, and leaves an owner's own promptCacheTtl as it is" (a file holding the owner's
    `promptCacheTtl: "1h"` keeps it byte for byte).
  - The replay harness (`install-lib.test.sh:208-231`) extracts setup's lines by pattern (`^old()`, `CACHE=$(old
    .cacheTtl)`, `^CACHE_ON=`, the `il_cache_ttl` gate, the Needs-you line); G17 replaces those lines, so the harness
    extracts G17's worker lines (the `old .workerCacheTtl` read, its `/config` merge, the `il_cache_ttl` gate on 5m or
    1h, the "not answered since 0.48.0" Needs-you line) and fails loud when a pattern matches nothing (each `grep`'s
    output must be non-empty, so a later rename cannot turn the cases into no-ops). Cases: a stored "recommended" or
    "default" is not an answer (`0:1`); a config with no answer is asked (`0:1`); a stored 5m and a stored 1h are each
    written on every replay and not asked (`1:0`); a stored leave writes nothing and is not asked (`0:0`); a /config
    `workerPromptCacheTtl` 5m beats a stored leave (issue 245) and answers a config with none (`1:0`); new "an old
    stored cacheTtl is no answer: nothing is written and the worker question is asked" (`replay '{"cacheTtl":"5m"}'`,
    `0:1`, the no-compatibility rule of Decision G17-1).
  - `scripts/__tests__/doctor.test.sh:115-147` (before its timed cases): the fixture config becomes
    `{"version": 1, "profile": "claude-openai", "mainCacheTtl": "1h", "workerCacheTtl": "5m", "chiefOfStaff": {"name":
    "r", "cacheTtl": "1h"}}`, with `.claude/main-session.settings.json` holding `{"env": {"CLAUDE_CODE_PROMPT_CACHE_TTL":
    "1h"}}` and the Builder fixture worktree's `settings.local.json` 5m. Kept with the new line count (3 `ok prompt
    cache` lines, one per role): "the relay's own 1h beats the user's 5m"; "a TTL in the main checkout's local file
    warns, naming the file, and the relay then runs 5m"; "a relay file without the key runs on the user's 5m, and the
    doctor says so". Replaced (main no longer reads a project or user TTL as its answer, F-c): :126-132 by "main's line
    names main-session.settings.json, and warns when that file's TTL is not main's answer" and "a user-level or
    project-level TTL does not change main's line"; :133-143 (`promptCacheTtl` in main's local file) by "a
    subagentPromptCacheTtl in main's local file that is not the worker answer warns, naming the file and the key" and
    "a local subagentPromptCacheTtl equal to the worker answer is ok"; :146-147 by "with every answer Leave as is the doctor
    prints one leave line per role and no warn" (`3:0`).
  Test: the three runs above green, and `rg -n '"promptCacheTtl"' scripts/__tests__` matches only the new
  "never writes promptCacheTtl" case and G17's settings.json absence checks.
- Old answers (the owner's rule: count first): installs that saved the old `promptCacheTtl` answer on this machine:
  0 (no `cacheTtl` or `chiefOfStaff.cacheTtl` in either project `commandeck.json` found under the home folder, no
  plugin entry in either Claude profile's `pluginConfigs`, no `~/.commandeck/install/`; checked 2026-10-25). The
  rest is unknowable. So no compatibility path: a saved `cacheTtl` or `promptCacheTtl` is read by nothing, and the
  CHANGELOG says to answer the three questions again. An install that setup wrote `promptCacheTtl: "5m"` into
  `.claude/settings.json` keeps it until uninstall (`uninstall.sh:42`, `il_cache_ttl ... off`, unchanged) or a hand
  edit (Accepted failure mode 2).
- The issue: issue 367, "Prompt cache per role: Chief of Staff, main and Builders, each 5m, 1h or leave", open
  (`gh issue view 367`, 2026-10-25, revision 1). Its number is on the Closes line, and goes in the batch brief and the
  CHANGELOG (Decision G17-7).

### G18 -- unregister the Chief of Staff Stop hook (item 7, host `24187ab2`)

- `hooks/hooks.json:104`: the `cos-unfinished-stop.sh` entry leaves the Stop list (the host commit removes only the
  registration). `docs/hooks.md:35`: the row goes; one sentence under the table says the script ships unregistered
  and how to register it. `hooks/cos-unfinished-stop.sh:1-7`: its header says it is not registered (the owner's
  order, 2026-10-25) and stays runnable for a project that registers it.
- The script and `hooks/__tests__/cos-unfinished-stop.test.sh` STAY: the owner's words are "disable that stop hook",
  and the host kept its file (Decision G18-1). The test runs the script directly, so it stays green; the fire-log
  coverage guard reads every top-level `hooks/*.sh` whether registered or not
  (`hooks/__tests__/hook-fire-log-coverage.guard.test.sh:32-36`), and the codex-parity guard flags only a `# codex:
  skip` marker on an unregistered hook (:29-30; the script has none).
- `scripts/__tests__/plugin.test.sh` has no hook count (:133-150 checks paths only), so the spec's "hook count" there
  is a new check, not a changed number: the hook is not registered and its script is executable.

### G20 -- the second plan judge runs on Fable (item 8, the owner's order of 2026-10-25, revision 2)

The host change, committed on host main as `abe1f341` (revision 3; read with `git show abe1f341`, 2026-10-25; it
matches the uncommitted diff revision 2 read, and its seventh file, the host platform audit's slice list, has no
plugin site): host routing gains
role `plan-judge-fable` (`agent: claude`, `model: claude-fable-5-1`, `effort: high`, `reviewer: true`, `tools: Edit,
Write, NotebookEdit`, `edits: false`); `plan-judge-astra` stays only because the host's platform audit launches its
auditor from that role's model; the host launch's Panel judges become `plan-judge-sol plan-judge-fable`; the host's
lane map puts `plan-judge-fable` in lane `review`; the host tests pin the eight roles, the Fable role's read-only
shape, the write-gate role list and the from-plan Panel cases on the Fable record. Mapped to the plugin:
- The plugin has no platform audit (`rg -n platform-audit` outside `.claude/` matches only CHANGELOG history), so
  the Astra judge role goes entirely: `config/routing.json:46-63` `plan-judge-astra` is replaced by
  `plan-judge-fable`: `{"agent": "claude", "model": "fable", "effort": "high", "reviewer": true, "tools": ["Write",
  "Edit", "NotebookEdit"], "unboxed": true, "edits": false, "note": "The Panel answer's second judge, beside
  plan-judge-sol: a read-only Claude pane on Fable at high that reads the plan and prints its findings; off, the
  other judge judges alone."}`. The model is the family `fable`, not the id: the plugin's routing note
  (`config/routing.json:9`) says a model is a family name that Claude Code resolves itself (to `claude-fable-5-1`
  today), and the host's own Claude roles name ids only because host routing does (Decision G20-1). No `claude`
  overlay and no codex fields (`sandbox`, `network`): the seat is Claude only, as on the host. The tools order is
  the plugin's (`plan-judge-sol.claude.tools`, :41), and `denies_writes` (`paths.sh:769`) already refuses a reviewer
  row that does not deny all three. `plan-judge-sol`'s note (:43) and `planJudgeSolEnabled`'s description
  (`.claude-plugin/plugin.json:128`) say "the Fable judge" for "the Astra judge".
- Options (`.claude-plugin/plugin.json:157-187`): the five `planJudgeAstra*` keys go; four `planJudgeFable*` keys
  take their place, `Enabled` ("Fable judge", default true), `Model` ("opus, sonnet or fable. project: fable"),
  `Effort` ("project: high") and `Fast`. No `planJudgeFableAgent`: the seat runs on Claude only, so an agent key
  would offer a Codex judge with no Codex model (Decision G20-2). `pp_role_key plan-judge-fable <field>`
  (`paths.sh:1090`) builds exactly those names, and `pp_role_has` finds no `Agent` key, so the role's routed agent
  (`claude`) is the agent.
- Readers: `scripts/plan-tier.sh:37-38` (`plan-judge-astra` -> `plan-judge-fable`, both arms);
  `scripts/builder-launch.sh:157` (the both-judges-off loop: `plan-judge-sol plan-judge-fable`; the plugin launch
  finds judge records by the `seat-<unit>-plan-judge-*` glob, :149, :170, :189, so it has no Panel judge list like
  the host's and no other line changes); `scripts/codex-helpers.sh:51` (`"plan-judge-fable": "planning"` in place of
  Astra's: the plugin's lane for plan judges is `planning`, beside `plan-judge-sol`, where the host's is `review`);
  `scripts/setup.sh:268` (`--profile claude` sets `codexReviewerAgent` and `planJudgeSolAgent` only: the Fable judge is
  Claude already).
- Text: `skills/setup/SKILL.md:155-156` (`Ask "Fable judge": Claude Fable high (recommended) | Off`, its `--option
  planJudgeFableEnabled=true|false` lines; the Astra parenthesis goes; the Claude-profile line names the Sol judge
  only); `skills/setup/SKILL.md:161` (revision 3: the "Fast tier" line's Judges choice sends `planJudgeSolFast` and
  `planJudgeFableFast`, not `planJudgeAstraFast`, which the manifest no longer has, so setup would send a key
  `setup.sh --option` refuses); `templates/main-session.md:65` (`plan-judge-fable` and `plan-judge-sol` both read it); `docs/configuration.md:20`
  (the row: `plan-judge-fable | Claude / fable | high | planJudgeFable + Model, Effort, Enabled, Fast | yes`);
  `README.md:111` ("Plan author, Sol judge, Fable judge") and `:244-248` (the Astra halves become Fable halves; the
  Agent row names the Sol judge only; the Model row says "fable on the Fable judge"). The CHANGELOG says the Panel's
  second judge now runs on Claude Fable and that saved `planJudgeAstra*` answers are read by nothing.
- Old answers (the plan spec's count-first rule, applied to this rename): saved `planJudgeAstra*` options on this
  machine: 0 (`~/.claude/settings.json` `pluginConfigs` has no `planJudgeAstra` key; no owner routing file
  `COMMANDECK_ROUTING` names one: no `routing.json` outside the plugin's own `config/` under the home folder, depth 6;
  no `~/.commandeck/install/`; checked 2026-10-25). Elsewhere unknowable. No compatibility path: an owner routing file
  kept from before gains `plan-judge-fable` from the plugin's defaults on the next setup (`il_routing_merged`,
  `setup.sh:257-261`), and its own `plan-judge-astra` entry stays, read by nothing (Accepted failure mode 6).
- Not changed: `README.md:110`, `skills/setup/SKILL.md:140-142`, `.claude-plugin/plugin.json:83`,
  `scripts/dashboard_limit.py:337` and the `codexReviewerModel=astra` tests (the Codex reviewer may still run Astra);
  fixtures that only name a seat record `plan-judge-astra` as data (`dashboard-built-planning.test.sh`,
  `dashboard-built-plan-worktrees.test.sh`, `transcript-requests.test.sh:219-224`, `seat-fence.test.sh:71-72`), which
  read records, not routing.
Tests (all existing files, nine with `seat-launch-github.test.sh`; `Timed checks` above for doctor.test.sh and
seat-run-refused.test.sh):
- `scripts/__tests__/plugin.test.sh`: new "the Fable judge is a read-only Claude reviewer on fable at high, and no
  Astra judge role is left" (`jq -r '.roles["plan-judge-fable"] | "\(.agent) \(.model) \(.effort) \(.reviewer)
  \(.edits) \(.tools | join(","))"'` is `claude fable high true false Write,Edit,NotebookEdit`; `.roles |
  has("plan-judge-astra")` is false; `rg -n 'planJudgeAstra|plan-judge-astra'` on `scripts hooks config templates
  skills docs README.md .claude-plugin`, tests excluded, is empty); the setup-answer row :62 becomes
  `planJudgeFableEnabled|true|Ask "Fable judge": Claude Fable high`; the option count (:76) follows section
  "Contracts". New (revision 3): "every option key setup's SKILL.md names is a manifest option" (each `--option
  <key>=` and each backticked `<key>Fast` word in `skills/setup/SKILL.md` is a key of `.userConfig`; prints the ones
  that are not, expected empty), which reads `planJudgeAstraFast` at :161 today and so fails until that line is
  renamed.
- `scripts/__tests__/seat-launch-github.test.sh` (revision 3; G20 turns it red otherwise: with the role gone its
  `plan-judge-astra` launch is refused as an unknown role, not for GitHub): the `cap` at :24 drops
  `"planJudgeAstraAgent": "codex"`; the role loop at :30 runs `plan-author plan-judge-sol plan-judge-fable builder`
  (the Fable judge is a Claude seat, probed as `plan-author` and `builder` are, so the expected refusal text and the
  check's name are unchanged; Builder check: if that run prints another refusal text for `plan-judge-fable`, the loop
  keeps three roles and a case of its own asserts the Fable seat's refusal, no pane and no record, with the text
  `seat.sh` prints); the models cache at :25 stays (a slug list, read by Codex seats only). Run: `bash
  scripts/run-shell-tests.sh scripts/__tests__/seat-launch-github.test.sh`.
- `scripts/__tests__/plan-tier.test.sh`: "Panel: the author and both judges, each on its agent and model" expects
  `plan-author claude opus,plan-judge-fable claude fable,plan-judge-sol codex gpt-6.1-sol`; "a judge on claude runs as
  itself on the Claude overlay: still two judge seats" expects `plan-judge-fable claude fable` in the middle; "sol
  off: Plan + judge runs the fable judge" and "sol off: Panel runs fable alone" (`plan-judge-fable claude fable`);
  "both judges off" sets `planJudgeFableEnabled`; "each seat prints its configured effort" expects `plan-author
  high,plan-judge-fable high,plan-judge-sol high`.
- `scripts/__tests__/seat-launch.test.sh:108-120`: the agent-switch loop runs for `sol:planJudgeSol` only; new case
  after it, "plan-judge-fable launches Claude Fable at high with Write, Edit and NotebookEdit denied (its record
  says so)" (`jrec plan-judge-fable` holds `claude --model fable --effort high --disallowedTools
  Write,Edit,NotebookEdit`); :129-130 "two judges on Claude are two seats with two records" reads
  `seat-pu-plan-judge-{sol,fable}.txt`. This is the plugin's read-only gate for a Claude seat (the plugin has no
  `seat-readonly-write-gate` test; the `--disallowedTools` flag is the gate).
- `scripts/__tests__/seat-run-refused.test.sh:40`: `plan-judge-fable:planJudgeFableEnabled` in the off loop.
- `scripts/__tests__/builder-launch-resume-from-plan.test.sh` (the plugin's from-plan judge cases): :75 and :81 set
  `planJudgeFableEnabled` (the cases "both judges off: the author's PLAN-DONE plan installs unjudged and the Builder
  opens", "both judges off: a PLAN-BLOCKED plan is still refused", "judges' Enabled keys holding a value they do not
  take: refused naming the key, nothing on main, no Builder"); the `judged ... astra` fixtures (:33, :36, :135, :137)
  write `fable` records.
- `scripts/__tests__/install-lib-setup.test.sh:43-44`: "--profile claude puts the reviewer and the Sol judge on
  Claude" expects `{"codexReviewerAgent":"claude","planJudgeSolAgent":"claude"}`.
- `scripts/__tests__/plugin-option.test.sh:104-112`, `:183-196`: the agent-switch and overlay lists (`own`, `seats`,
  `keys`, `direct`, `seven`, the `conf` at :192) name `codex-reviewer` and `plan-judge-sol` only, and each expected
  string (`SHIPPED`, `OPUS`, `CONTRACT`) loses its third part: those cases switch a role's agent, which the Fable
  judge has none of.
- `scripts/__tests__/doctor.test.sh:213` (revision 4, CORRECTED: both anchored groups on that line change): the
  doctor groups roles in `config/routing.json`'s key order (`doctor.sh:150-154`, `keys_unsorted`; on `9ac91d3`
  `orchestrator, plan-author, plan-judge-sol, plan-judge-astra, builder, fixer, codex-reviewer`), and G20 puts
  `plan-judge-fable` in `plan-judge-astra`'s place, a Claude seat that `pp_role_enabled` passes by default, so the
  check "the doctor reports a seat type that cannot reach GitHub, with its sandbox and the reason, and exits 1" expects
  `^FAIL github read: codex read-only + network (plan-judge-sol): no network in the sandbox: error connecting to
  api.github.com` and `^ok   github read: claude, no sandbox (orchestrator, plan-author, plan-judge-fable, builder,
  fixer)$` (still `1:1:1`); its case name stays. If the Builder places the role elsewhere in the file, the expected
  list follows the file's key order (`jq -r '.roles | keys_unsorted'`), stated in the evidence file. Run: `bash
  scripts/run-shell-tests.sh scripts/__tests__/doctor.test.sh` (edited in place, no fixture added before its timed
  cases).
- `scripts/__tests__/doctor.test.sh:217`: the Codex read-only group is `(plan-judge-sol)`; :218-224 keeps its
  case "a seat whose own environment cannot read GitHub fails alone, though another seat of its agent and mode
  reads" with a second Codex seat made in its routing fixture (`.roles["plan-judge-fable"] = .roles["plan-judge-sol"]
  + {shellEnv: {GH_TOKEN: "invalid"}}`), so the group reads `(plan-judge-sol)` ok and `(plan-judge-fable)` FAIL.
  Break: scripts/__tests__/seat-launch.test.sh -- plan-judge-fable launches Claude Fable at high with Write, Edit and NotebookEdit denied (its record says so) -- config/routing.json plan-judge-fable's tools list
  Break: scripts/__tests__/plugin.test.sh -- the Fable judge is a read-only Claude reviewer on fable at high, and no Astra judge role is left -- config/routing.json plan-judge-fable's edits false and reviewer true
  Catches: a Panel plan judged by a seat that can edit the plan it judges, or a Panel still launching the Astra judge
  after the owner's order.

### G19 -- the review threshold: issue 366 (gated on the host commit; second to last, G21 after it)

Gate: the Builder builds G19 only after the host unit review-threshold-2026-10-25 has merged on the host's local
main. CORRECTED (revision 5): a subject search for the unit name is no gate, since host main already holds
`1b65d5bd docs(plans): review-threshold-2026-10-25 plan`, a plan-only commit. The gate needs both the host's merge
commit for the unit (the host's local merge titles it with the unit as the scope, `<type>(<unit>): ...`, from the
unit's first `feat(` subject, host `merge-unit-local.sh:602`, e.g. `feat(<unit>): Builder pass r1`; a `docs(`
subject does not count) and the implementation on host main. On reaching G19 it runs:

    H=<host repo>
    c=$(git -C "$H" log main --format='%h %s' -E --grep='^[a-z]+\(review-threshold-2026-10-25\)' | grep -v ' docs(' | head -1)
    f=$(git -C "$H" show main:.claude/scripts/builder-codex-pass.sh 2>/dev/null)
    if [ -n "$c" ] && grep -q 'REVIEW_CAP' <<<"$f" && grep -q 'passes_on_record' <<<"$f"
    then echo "G19 gate PASS: $c"; else echo "G19 gate FAIL: commit=${c:-none}"; fi

Pass: `G19 gate PASS: <sha> <subject>`, and the port follows that commit. Fail: `G19 gate FAIL: ...` (a missing
commit, or a commit without `REVIEW_CAP` and `passes_on_record` in the pass script). Run 2026-10-25: `G19 gate FAIL:
commit=none` (the `--grep` regex skips `1b65d5bd`; the pass script has neither name). On a fail it asks main
(`ask-main.sh`) and builds nothing of G19 until main answers. When the host commit lands,
the port follows THAT commit, not this section: where the host plan (read 2026-10-25 from the host's planning
worktree, not on host main, being edited that day) and the host commit differ, the commit wins. Issue 366's text
and its additions O1-O6 are the scope. If main answers "ship without G19", issue 366 leaves the Closes line.

The host plan's rule points and the plugin sites they map to (re-read on `9ac91d3`):

| Rule | Host site | Plugin site (~line) | Plugin test (`scripts/__tests__/builder-codex-pass-threshold.test.sh`, new) |
|---|---|---|---|
| 1 threshold: no open P0-P2 ends the loop; P3 never holds it (O1: open, old or new) | `session_proof` verdict, `FORMAT` verdict line, the post-pass stop block | `session_proof` :337 (the finding-line match, `P[0-3]`), `FORMAT` :103, after the round file :1361 | "a P3-only pass ends the loop"; "an open carried-over P2 holds the loop" |
| 2 cap 5: at the cap open findings are filed and the unit merges | `REVIEW_CAP=5`, `passes_on_record` beside `round_files`; review run as final at the cap; `--verify` rule `cap stop` | beside `round_files` :357; `--verify` :548-600 | "pass 5 with an open P2 files it and merges"; "the pass number is not the count" |
| 3 P0/P1 never capped; O4 stop two passes after the cap | `--verify` refuses any P0/P1; `REVIEW STOP` at count 7; launch gate before the commit | `--verify` :568; before `stage_and_check` (:1028); the decisions ledger through `decision.sh` (the merge reads it at `merge-unit-local.sh:229`) | "pass 5 with an open P1 runs pass 6"; "a P1 open at pass 7 stops the unit with one question" |
| 4 fresh closing reviewer (O2: keeps decisions, accepted failure modes, stated limits) | a closing code pass sends no EARLIER, DEFERRED, SITES or NEWCODE block; `ACCEPTED_HEAD`; `--verify` skips the handed-findings check | `REST` :1153 (`EARLIER` :837, `DEFERRED` :1146, `SITES`/`NEWCODE` :944-960); `ACCEPTED` through G5's `plan_section`; `--verify`'s earlier-pass checks :590-600 | "the closing prompt carries decisions and accepted failure modes but no earlier findings" |
| 5 file, then merge (O5: one issue per class, a duplicate commented) | `--verify` prints `Open finding:` lines; `merge-unit-local.sh --filed '<class>=#<n>'` and `check_filed` at steps 1 and 3 | `merge-unit-local.sh` `prove` (step 1 :271, step 3 :284-288), squash message :401-416, `gh` already used at :303-307 | "the merge refuses until the open findings are filed"; "two findings of one class file one issue"; "a duplicate comments instead of filing" |
| O3 rubric, no lowering | `FORMAT` rubric sentence; severities from the reviewer's record, never the round file | `FORMAT` :103; `session_proof` | "a severity lowered in the round file changes nothing" |
| O6 measure | the host's unit ledger | no plugin ledger of rounds by severity: the Builder records which plugin record holds passes and findings by severity (the dashboard's `units.finishedBuilds[]`, `merge-unit-local.sh:594-604`) and ports the field; none: a follow-up issue, said in the CHANGELOG | none, a measurement for main |

- The plugin's issue-325 rule (a finding blocks only when normal use would hit it; bypass and odd-setup findings go
  under `KNOWN GAPS:`, `FORMAT` :103, `builder-codex-pass.sh:26`) stays beside the threshold unless the host commit
  removes the host's equivalent (Decision G19-2).
- Break lines (the host plan's, mapped; the Builder renames them to the host commit's final labels):
  Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- the pass number is not the count -- scripts/builder-codex-pass.sh passes_on_record replaced by $N
  Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- a P1 open at pass 7 stops the unit with one question -- scripts/builder-codex-pass.sh the launch gate before stage_and_check
  Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- the closing prompt carries decisions and accepted failure modes but no earlier findings -- scripts/builder-codex-pass.sh the closing-pass emptying of EARLIER, DEFERRED, SITES, NEWCODE
  Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- the merge refuses until the open findings are filed -- scripts/merge-unit-local.sh the step 3 check_filed call
  Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- a filed issue must be open -- scripts/merge-unit-local.sh check_filed's gh state test
  Catches: a P3-only loop that runs on for nits; a unit that never ends below P2; a closing reviewer anchored by the
  author's history; a unit merged with an open finding no issue tracks.
- Text: README review section and `docs/` review pages describe the new default (issue 366's Done when; this is not
  the release README rewrite the owner deferred, Decision V-1); `templates/_builder-brief-template.md` steps 2-3
  (stop lines end the loop; never lower a severity).
- Size: ~450 changed lines (the host plan plans 380 on its side; the plugin adds the merge's `--filed` and the
  docs), an estimate until the host commit exists.

### G21 -- Builder speed: the post-fix checks at once, cheaper hooks (item 9, LAST; gated on the host commit)

The owner's order (2026-10-25, ~22:08 ET): a unit for the Builder-speed items, added to this unit. It ports the host
unit builder-speed-2026-10-25: F36, the post-fix checks run at the same time, each exit code reported, the round
waiting for all of them; F35, per-call hook overhead cut with NO check removed or weakened (every hook that runs for a
Builder today still runs and blocks the same inputs; a change that alters any check's outcome on any input is out of
scope and goes to main as a question).

Gate (as G19's): the Builder builds G21 only from the judged host plan once that plan's judge said GO, and ports the
host differences after the host merge. CORRECTED (revision 5), as G19's: host main already holds `cf1846ec
docs(plans): builder-speed-2026-10-25 plan` and `8b6ab6c4 chore(tests): empty post-fix-checks test file for
builder-speed-2026-10-25`, neither the implementation. The judged host plan on host main
(`.claude/plans/builder-speed-2026-10-25.md`, Cut 1) names first the runner `.claude/scripts/post-fix-checks.sh` and
its `package.json` script `test:post-fix`. On reaching G21 it runs:

    H=<host repo>
    c=$(git -C "$H" log main --format='%h %s' -E --grep='^[a-z]+\(builder-speed-2026-10-25\)' | grep -v ' docs(' | head -1)
    if [ -n "$c" ] && git -C "$H" cat-file -e main:.claude/scripts/post-fix-checks.sh 2>/dev/null \
      && git -C "$H" show main:package.json | grep -q '"test:post-fix"'
    then echo "G21 gate PASS: $c"; else echo "G21 gate FAIL: commit=${c:-none}"; fi

Pass: `G21 gate PASS: <sha> <subject>`. Fail: `G21 gate FAIL: ...`. Run 2026-10-25: `G21 gate FAIL: commit=none`
(`8b6ab6c4`'s scope is `tests`, so the regex skips it; the runner is not on host main). On a fail it asks main
(`ask-main.sh`) and builds nothing of G21 until main answers. Where the host plan and the host commit differ, the commit wins. Hard cut-off: if the host unit is not merged
on host main by 03:00 ET, 2026-10-26, the plugin ships without item 9; main says so, the Builder does not decide (it
asks, and on "ship without G21" leaves G21 out and goes to the version step). G21 has no plugin issue; nothing on the
Closes line depends on it.

State of the host plan (revision 3): not written yet (its planning worktree had no `builder-speed-2026-10-25.md`,
checked 2026-10-25 ~22:15 ET). Its spec, on host main's briefs, names the scope above, the host's three checks
(backend typecheck, test-config typecheck, changed tests), a measured profile before any change, a parity test that
runs the old and new hook paths over the same inputs and compares block, allow and message, and failure paths for
every new parallel process. So the map below is the plugin side as far as the spec allows; every "from the judged
host plan" cell is filled from that plan when its judge says GO. (Revision 5: the host plan is now on host main,
`cf1846ec`; only the gate above was re-read from it, and the map is unchanged.)

| Host site (from the host spec) | Plugin site (~line, on `9ac91d3`) | Plugin test |
|---|---|---|
| F36: the one home where the post-fix checks are prescribed: the Builder brief template | `templates/_builder-brief-template.md:94-105` (before any test run; a fix round re-runs only the files it touched) | `scripts/__tests__/brief-template.test.sh`, a text check named from the judged host plan |
| F36: the fix brief's verify text | `scripts/builder-codex-pass.sh:1426-1470` (the fix brief writer; its touched-test list :1470) | `scripts/__tests__/builder-codex-pass.test.sh`, from the judged host plan |
| F36: a helper that runs the three checks | none today: the plugin runs no typecheck; its post-fix checks are `run-shell-tests.sh` on the touched files and, for a plugin unit, `claude plugin validate .` and `claude plugin test .` (Done when 2). Which run at once, and in what helper, from the judged host plan | from the judged host plan (it names the test that fails if they run in sequence again or a failed check's code is dropped) |
| F36: the PC offload | `scripts/peer-offload.sh`, called by `run-shell-tests.sh:120-133` | `scripts/__tests__/run-shell-tests.test.sh` (its timed cases stay first) |
| F35: the hook wiring | `hooks/hooks.json`: PreToolUse Bash 7 hooks, Edit\|Write\|MultiEdit 8 and Write 1, Read 1; PostToolUse Bash 5, Read 2, Write 1, `.*` 1; Stop 5 (read with `jq`, 2026-10-25) | `scripts/__tests__/plugin.test.sh` (:133-150 checks every registered path) |
| F35: the 17 host edit guards | the plugin's 8 Edit\|Write\|MultiEdit guards (`main-edit-guard`, `merge-lock-guard`, `edit-content-tripwires`, `literal-secret-warning`, `test-skip-only-blocker`, `dependency-addition-guard`, `file-size-cop`, `write-existing-file-guard`) and `new-test-file-guard` (Write) | each guard's `hooks/__tests__/<guard>.test.sh`, unchanged assertions; `write-existing-file-guard.sh` has no test file today, so if G21 changes it, its test comes first |
| F35: host `typecheck.sh`, `brief-freshness-gate.sh` (PostToolUse Edit) | none: the plugin has neither hook | none, no plugin site |
| F35: one dispatcher process or skipping work by file type (candidates in the spec, not orders) | `hooks/lib/run-hook.sh` (every hook starts through it) and the guards above | the parity test, its plugin path and name from the judged host plan (`hooks/__tests__/<name>.test.sh`) |
| F35: the measured profile | `hooks/lib/hook-fire-log.sh` already records `ms_body` per fire (:33-37), summed by `scripts/hook-fire-log-summary.sh`, in `~/.claude/hook-fire-log/<project>.<date>.jsonl` | none, a measurement in the evidence file |

- Profile first (Builder check A8, before any G21 edit): `bash scripts/hook-fire-log-summary.sh` over this
  project's Builder sessions gives per-hook calls and `ms_body` totals. `ms_body` starts at arming, so it leaves out
  each process's start (`run-hook.sh` plus Bash): the Builder also times one guard's whole call (`time bash
  hooks/lib/run-hook.sh hooks/<guard>.sh < <payload>`) and records both. A profile with no plugin Builder rows: the
  Builder records that and ports only the host changes whose saving does not depend on the host's numbers.
  Catches: a hook change chosen by the host's numbers that saves nothing in the plugin, whose hooks differ.
- Rules carried from the host spec: no guard removed or weakened (each changed hook's existing test stays green with
  its assertions unchanged, plus the parity test); a guard that crashes still blocks, as today; a skipped guard for a
  file type is shown unable to block that type by its own matcher; every new parallel process says what a failed,
  killed or concurrent call leaves behind.
- `Break:` lines, `Catches:` lines and What can go wrong rows: from the judged host plan, mapped to the sites above
  and added to this plan's sections (one `## Plan change log` line) before the first G21 edit.
- Shared files: `templates/_builder-brief-template.md` and `scripts/builder-codex-pass.sh` after G19;
  `hooks/hooks.json` after G10.
- Size: ~250 changed lines over ~8 files not already in this plan, an estimate until the judged host plan exists.
- BUILT FROM THE HOST COMMIT (fix round 3; host `da69812c`, merged on host main as `32d4831e`; main's order). F35:
  the host removed its only hook change (the tokenizer memo) by its own acceptance rule (p50 0.90-0.97 of base
  against a 0.8 bar), so no hook change is ported; A8's profile is in the evidence. F36: new
  `scripts/post-fix-checks.sh [<test file>...]` starts the post-fix checks at once, each under `timeout` (540 s, below
  the Bash tool's 600 s; `POST_FIX_CHECK_TIMEOUT_S` only so a test reaches the timeout in seconds), output to its own
  log in a new `$PP_SCRATCH/post-fix.XXXXXX/` (kept for the evidence; a failed mkdir exits 2 before any check
  starts): `shell`, `bash scripts/run-shell-tests.sh <the files>` (no files: no shell check); and in a plugin
  checkout (`.claude-plugin/plugin.json` at the top), `validate`, `claude plugin validate .`, and `mods`, `claude
  plugin test .`. It waits for each pid into its own slot and computes the exit once, after the last: 0 all green, 1
  any red, timed out or interrupted, 2 nothing started. One line per check `post-fix: <name> exit <rc> (<s>s) <log>`
  (124/137: `timed out after <n>s`), the last 30 lines of each red log, then `post-fix: all green` or `post-fix: <k>
  of <n> failed: <names>`. INT, TERM or HUP: TERM each check, wait, `post-fix: interrupted: <name> cut off` per
  unfinished check, exit 1. One home: `templates/_builder-brief-template.md` "While building" names it; the fix
  brief's touched-test list is unchanged (as the host left its own). The host's npm name for the rerun guard has no
  plugin site: `hooks/suite-rerun-guard.sh` keys npm, tsc and vitest calls only, not `run-shell-tests.sh`.
  Catches: post-fix checks run one after another, and a red check's code lost behind a later green one.
  Break: scripts/__tests__/post-fix-checks.test.sh -- runs every check at once -- scripts/post-fix-checks.sh the start without `&`
  Break: scripts/__tests__/post-fix-checks.test.sh -- two failures keep their own codes -- scripts/post-fix-checks.sh exit with the last check's status only
  Break: scripts/__tests__/post-fix-checks.test.sh -- an early failure survives later successes -- scripts/post-fix-checks.sh one failure flag reassigned from each wait

## Rule drift map

Copied from the judged plan. The owner ruled that the unit copies EVERY line of the drift list (R1-R24); a line an
ordered item covers rides with it, every other line is its own item. Lines covered by part A1's groups are done
(0.47.0). Main marks each synced in the host's drift tool after the merge.

| Line | Host section | Plugin target | Covered by |
|---|---|---|---|
| R1 | short brief template | `templates/_batch-brief-template.md` | done in A1 (What can go wrong :54-61, size line) |
| R2, R3 | brief template: Accepted failure modes, Decisions already made | plan specs, reviewer prompt | issue 362 (done in A1); the reopen rule: RD1 |
| R4, R23 | brief template: Stated limits | plan specs, reviewer prompt | RD2 |
| R5-R7 | Builder brief: Codex passes, Done, How to work | `templates/_builder-brief-template.md` | issues 352, 362 (done in A1); 359, 365 (G5) |
| R8-R11 | reviewer tools | reviewer prompt, Builder brief How to work | RD3 |
| R12 | routing roles | `config/routing.json` roles | RD4 |
| R13 | main session: Orchestrator and Advisor Role | `templates/main-session.md` :11-13 | issue 353 (done in A1); the changed sentence is RD11 |
| R14 | orchestration reference: Resource safety | `templates/global-rules.md` Working and review | RD5 |
| R15, R16 | orchestration reference: Unit, Visibility and ledger | `templates/global-rules.md` Working and review | RD6 |
| R17 | adversarial reviews | `templates/global-rules.md` Working and review | RD7 |
| R18 | comments: never write the add-on's name in a comment | `templates/global-rules.md:55-58` | already present; RD8 dropped (G5 rewords the line) |
| R19 | planning rules | `templates/global-rules.md` | issues 359, 365 (G5) |
| R20 | startup: Operating Rules | `templates/AGENT_STARTUP.md` Rules for every pane (:70) | RD9 |
| R21 | brief template: Assumptions, Claims to falsify, Plan change log | plan specs | issue 359 (G5) |
| R22 | brief template: Data design, Prior art | `templates/_batch-brief-template.md:46-52` | RD12 |
| R24 | agents: Compact Instructions | `templates/global-claude.md` | RD10 |

## Rule drift items (G12, built after G9)

Each is rule text unless it says otherwise; each test is a text check in `scripts/__tests__/brief-template.test.sh`
unless named. No item adds a conditional write or safety check, so none has a `Break:` line.

- RD1 (R2, R3). Reopen rule. `builder-codex-pass.sh` `LIMITS_HEAD` (:173) and the plan-author lines
  (`seat.sh:412-416`): a finding reopens an accepted failure mode, a decision or a stated limit only when it proves
  the item's factual premise false or shows the goal defeated, with a concrete counterexample; reviewers cite the line
  otherwise. ~10 lines. Test: builder-codex-pass.test.sh "the review prompt reopens a decision only on a concrete
  counterexample".
- RD2 (R4, R23). Stated limits heading: `(every reviewer is handed these; a finding beyond one is out of scope: a
  follow-up issue, never a blocker)`, in `LIMITS_HEAD` and the plan-author lines; each limit is a measured bound. It
  governs later plans; this unit's order (every finding blocks) is unchanged. ~6 lines. Test:
  builder-codex-pass.test.sh "a finding beyond a stated limit is a follow-up, never a blocker".
- RD3 (R8-R11). The reviewer prompt (`builder-codex-pass.sh` `FORMAT` :103, `GUIDANCE` :110) and the Builder brief's
  How to work. Copied (the judged text, `.claude/plans/plugin-port-2026-10-25.md:802-813`, word for word): a P0-P2
  finding carries a complete failing test file in a fenced block naming its path, written to fail on the diff as it
  stands, or its exact failing input when a test would cost more, with the reason in one line; a P2 or P3 whose test
  is written and whose fix is under ten lines may carry the fix as a fenced unified diff (the Builder applies it, runs
  the test green, and the next pass reads it; a reviewer never reviews its own fix); the brief and the dispatch spec
  outrank the startup file and every skill, and a reviewer that stops early quotes the instruction that stopped it;
  inside the read-only sandbox an Orca call answering `runtime_unavailable` is by design, not a failure to retry or
  report; read the diff, then the brief, draft the findings, and only then the evidence file; open a file outside the
  diff, the brief and its named callers only to confirm or refute one finding, and say which; never open a generated
  file. No plugin site: the host's test runners, file paths and model-pausing note. ~30 lines. G15 edits the same `FORMAT` after RD3. Test:
  builder-codex-pass.test.sh "the review prompt carries the failing-test default, the cold-read order and the scope
  rule" (its greps include `whose test is written and whose fix is under ten lines`).
- RD4 (R12). `config/routing.json` `roles.fixer.first` (today `{"model":"opus","effort":"high"}`) becomes
  `{"model": "builder", "effort": "builder"}`, the value `builder-fresh-round.sh:128-130` already reads; the
  `fixerFirstModel`/`fixerFirstEffort` descriptions (`.claude-plugin/plugin.json:45-58`) and the fixer note say so. A
  behaviour change for installs that keep the default: the CHANGELOG says it. ~8 lines. Test: builder-fresh-round.test.sh
  "with no /plugin key the first fix round keeps the Builder's launched model and effort" (after its timed cases).
- RD5 (R14). Resource safety, as plugin meaning: no duplicate agent of any role (already `global-rules.md:70`); never
  stop a driver and relaunch it without reading its log tail; after a crash resume, never restart (`claude
  --continue` or `codex resume --last`, then "Orca restarted; continue from your last message."); interrupt before
  closing a resumable pane, close reviewers after their verdict; memory, not a pane count, is the limit
  (`config/pane-budget.json`). No plugin site: the host's node heap flag, lane counts, cgroups, systemd scopes, pane
  box, machine figures and typecheck cache. Not copied: "never launch agents with setsid or nohup" (Decision RD-1).
  ~10 lines. Test: brief-template.test.sh "global rules carry resource safety: log tail before a relaunch, resume
  never restart, memory is the limit".
- RD6 (R15, R16). Units and visibility: one unit is one worktree, one branch, one squash merge; never two workers in
  one worktree, and units touching the same files are combined; a ready brief is dispatched at once unless it
  overlaps another unit (serialize only overlaps); main removes the unit's panes and worktree in the merge turn and
  reconciles orphaned worktrees at every plan start; briefs run ahead of builds; main verifies every dispatch (status
  shows only scope, the diff stat matches each claimed change, the worktree and main heads are as expected, a pass
  claim carries runner totals); every worker is an Orca pane the owner can open, Orca's task list is the dispatch
  ledger, and anything main did not start is reconciled before acting. No plugin site: the host's repo id, paths and
  model limit. `global-rules.md:60` keeps its units-by-area line. (Revision 2: restored word for word from the judged
  plan, `plugin-port-2026-10-25.md:830-837`.) ~16 lines. Test: brief-template.test.sh "global rules carry one unit
  per worktree and the dispatch ledger", whose greps include `serialize only overlaps`, `status shows only scope`,
  `the diff stat matches each claimed change`, `the worktree and main heads are as expected` and `a pass claim
  carries runner totals`.
- RD7 (R17). Adversarial reviews: every reviewer covers the same full scope; no reviewer test runs at round close,
  each goes to the fixer; code comments never name reviewers, rounds or P-levels; a reviewer's findings are read with
  `read-verdict.sh`, never a raw pane read. ~6 lines. Test: brief-template.test.sh "global rules carry the
  adversarial review lines".
- RD8 (R18): DROPPED, already in place at `templates/global-rules.md:55-58` (never write the add-on's name as a
  comment tag, explain a simplification plainly, old tags change only when edited or in a requested sweep). G5
  rewords its "ponytail skill" clause (Decision RD-3).
- RD9 (R20). `templates/AGENT_STARTUP.md` Rules for every pane (:70) gains what it lacks of: own in-scope work end to
  end; plan first for multi-step work and read the real code before editing; before editing auth, verification,
  billing, tenant isolation or deploy tooling, write the plan down and list every caller of what changes; fix every
  in-scope copy of a bug pattern; confirm first before an irreversible destructive action, and no destructive git
  command unless asked. The refusal line is there already (:77). ~8 lines. Test: brief-template.test.sh "the startup
  file's pane rules carry plan-first, callers before risky edits and confirm before destruction".
- RD10 (R24). `templates/global-claude.md` gains `## Compact Instructions`: keep the task or brief path and the
  evidence file path, the current cut and its test state, the last round file and its open findings, open decision
  ids and the files changed; drop file dumps and tool output. Main still never compacts (`templates/main-session.md:35`).
  ~5 lines. Test: install-lib-setup.test.sh "the global CLAUDE.md template carries Compact Instructions" (that file
  reads `global-claude.md` today, with plugin.test.sh).
- RD11 (R13). `templates/main-session.md:9` (the Do-not row "an edit to project code -> a batch brief") becomes "a
  large code change in main -> a batch brief, then `builder-launch.sh`"; :11-13 say main may make a small code fix
  itself, with the main-edit guard off (`hooks/main-edit-guard.sh:72` reads `.claude/approvals/main-edits-ok`; the
  owner creates it), larger work runs as a Builder, and main's code takes the same review and merge rules. No guard
  code changes. ~6 lines. Test: brief-template.test.sh "main's rules let main make a small code fix with the
  main-edit guard off".
- RD12 (R22). `templates/_batch-brief-template.md` Data design (:46-52): the placeholder line (:52) gains `; a half
  write leaves <what>, recovered by <how>; two concurrent writes <result>; retries owned by <code>, at most <n>`.
  ~5 lines. Test: brief-template.test.sh "the batch template's Data design asks for half-write recovery, concurrent
  writes and retry ownership".
- RD13 (the owner's order of 2026-10-25). `templates/main-session.md:7` and `templates/_builder-brief-template.md:128-129`:
  every test run starts with Bash `run_in_background`, whatever its length, and every other command that can run in
  the background does; only quick reads stay in the foreground; the "over 60 seconds" qualifier goes (:128). ~6
  lines. Test: brief-template.test.sh "every test run starts in the background whatever its length, in main's rules
  and the Builder brief".

## Decisions

1. G5-1. Old `ponytail:` comment tags in code stay (issue 365, not in scope). Test: none, out of scope by the issue.
2. G5-2. No cleanup of existing installs: 0 here, unknowable elsewhere; `config/retired.tsv` gains a lint row only.
   Test: rules-audit.test.sh "a retired --ponytail in a template is flagged with what replaced it".
3. G5-3 (CORRECTED). Issue 359 item 5c adds one `CLAIMS` block after the diff, read by `plan_section`, the
   existing What can go wrong awk made a function. Test: builder-codex-pass.test.sh "the review prompt places the
   plan's claims after the trace instruction".
4. G5-4. The host commit's every-pane `ponytail@ponytail: false` is not ported: the plugin stops managing the
   third-party plugin and never turns off one the owner enabled. Test: worktree-setup.test.sh "a fresh Builder
   setup writes no ponytail@ponytail key".
5. G5-5. The pre-fill example key in plugin-option.test.sh is `relayPromptCacheTtl`, which G17 keeps, so G17 does
   not rewrite G5's cases. Test: plugin-option.test.sh green after G17.
6. G8-1 (REDESIGNED, fix rounds 2 and 4). Tmp-worktree ownership has two proofs, both of one add: the add's own
   success, which PostToolUse sees only when the command is on the fixed list (G8 357: `git [-C <dir>] worktree add
   <options from a list> <path> [<commit>]`, nothing else), and the claim beside the path, written by that add's
   PreToolUse while the path was absent and not replaced since by another hooked add's. A path's look before the add
   alone (the old `pending` line), a command that exited 0, the worktree at the path when the record step runs, and
   noclobber alone prove nothing: two sessions can both see the path absent, `; true` hides a failed add,
   `--version` exits 0 with no add, and a record step can run after the worktree was removed and the path re-added.
   The grant lives in the worktree's own git dir and goes with it; the forced remove that uses it must be on the
   fixed list too. Test: git-safety.test.sh "removing a tmp worktree this session added is allowed"; "session B's
   failed add on session A's worktree path, then B's forced remove: blocked, A's worktree and its uncommitted file
   still there"; "a failed add followed by `; true` grants nothing"; "every ownership ordering found so far, in
   order".
7. G8-2 (CORRECTED). The third timed pre-review step is the full suite, the plugin's only step after the rebase's
   tests. Test: builder-codex-pass-rebase.test.sh "a closing pass's report carries one timing line per pre-review
   step".
8. G9-1. The pass watcher is a dashboard alert, not a fifth watcher. Test: dashboard-alerts.test.sh "a pass-4 NO-GO
   raises pass-loop once and a GO raises none".
9. G9-2. The order file is written only when the Chief of Staff adds anything. Test: cos-order-check.test.sh "an
   order file without the owner's-words section is flagged".
10. G10-1 (CORRECTED in revision 3). The mod reads the dashboard snapshot through G10's snapshot adapter: this
    project's object `projects[PP_PROJECT].units` (not a top-level `units`), its rows' fields under the host's names
    (`inFlight[].stage`, `.round`, `.ageSec`, `.agents`, `.builder.verdict`, `.verdictRound`, `.findings`,
    `.cost.stages`, `.issues`, `.built`, `.startedAt`; `finishedBuilds[].cost.total.usd`), and merge time from
    `finishedBuilds[].at` (pass 1: not `mergedSincePush`, which a push empties); no push chain. Before the port the Builder records the table in the
    evidence file against a real `data.js`. A missing field renders nothing. Test: units-sources.test.tsx "a plugin
    snapshot's project units, merge times and costs parse" (the judge's input); "a snapshot without this project, or
    with no unit list, draws nothing and says why"; units.test.tsx "a unit merged today from a plugin snapshot shows
    in the pane's merged-today line".
11. G10-2. With no live units every view draws nothing. Test: units.test.tsx "no live units: no band row, no pane,
    no status line".
12. G10-3. No stall mechanic anywhere. Test: units.test.tsx "a unit with an old worktree shows no stall mark and
    raises no toast".
13. G10-4. The port includes `8fb27eff` and `fdb79064`. Test: units.test.tsx "issues built count the evidence while
    building and every issue once the build is done"; "a refusal shows its step and reason in the pane and /units,
    and nothing in the band".
14. G10-5 (NEW; revised in revision 1). The merge gate runs only when the merged tree is a plugin
    (`.claude-plugin/plugin.json`), and then on every merge path: its own block after the check, with its own copy of
    the merged tree, run with no `testCommand` and when the suite proof is reused; red refuses the merge.
    Test: merge-unit-local.test.sh "a project that is not a plugin, with a changed hooks/x.ts, runs no claude plugin
    test"; "a plugin unit changing hooks/x.ts with no testCommand runs claude plugin validate and test on the merged
    tree"; "a red claude plugin test refuses the merge and leaves main where it was"; merge-queue.test.sh "a merge
    that reuses the closing pass's green suite still runs claude plugin test on a plugin unit".
15. G11-1. Nothing is tagged, published, backfilled or written as release notes in this unit; main runs the
    backfill after the push, on the owner's go, once all plugin work is merged. Test: release-notes.test.sh
    "backfill --plan lists every version oldest first and creates nothing".
16. RD-1. The setsid line of R14 is not copied: the plugin's detach is the 0.46.0 fix for a seat run dying with
    main's pane. Test: `scripts/__tests__/seat-run.test.sh`, its existing setsid case (unchanged).
17. RD-2. Host-only sentences are listed per item with the reason. Test: none, a reviewer reads each item's "No
    plugin site" list against the host section.
18. RD-3. RD8 is dropped: its rule is at `global-rules.md:55-58`. Test: none, the line exists and G5 only rewords
    its add-on clause.
19. G15-1. Only the `FORMAT` sentence is missing; the plugin's class tag and KNOWN GAPS stay, and a known gap carries
    no Class search line (`class_sites` already refuses one there). Test: builder-codex-pass-suite.test.sh "the pass
    prompt asks for a Class search line under each blocking finding".
20. G16-1. A design-only pass is a `final` that made a commit touching nothing outside `.claude/plans`,
    `.claude/briefs`, `.claude/metrics` (the host's rule). Test: builder-codex-pass-closing.test.sh "a final whose
    commit changes only the plan reads under the design head, says so, and its round file says design".
21. G16-2. `--verify` refuses a design-only pass; the code after it runs as a closing pass whose GO merges. Test:
    builder-codex-pass-closing.test.sh "its GO merges nothing"; "the code written after it runs as a closing pass
    whose GO merges".
22. G16-3 (revised in revision 1). main-watch names the next step for a design GO, in wording of its own: a
    narrowed GO keeps "Finished on a narrowed pass", a design GO says "Finished on a design-only pass", as host
    `95730a8d` keeps them apart. Test: main-watch-report-wake.test.sh "a design GO's report names writing the code and
    the next final pass, not a merge"; "a DONE after a design GO is posted as finished on a design-only pass, not as
    narrowed, and is not merged"; the existing narrowed case (:47-55) unchanged.
23. G17-1. Three options named by role, `promptCacheTtl` removed, no compatibility path (0 saved answers here).
    Test: plugin.test.sh "option mainPromptCacheTtl defaults to setup's recommended answer (1h)" and its
    `workerPromptCacheTtl` (5m) and `relayPromptCacheTtl` (1h) rows.
24. G17-2. Main's TTL goes only into `.claude/main-session.settings.json`, through `il_main_lean`'s ownership rule.
    Test: install-lib-setup.test.sh "setup writes main's TTL only into main-session.settings.json: main's
    settings.local.json and .claude/settings.json get none". Revised in revision 4 (Decision G17-11): leave writes
    nothing; see there.
25. G17-3. `.claude/settings.json` keeps only `subagentPromptCacheTtl`, from the worker answer; `promptCacheTtl` is no
    longer written. Test: install-lib.test.sh "il_cache_ttl writes subagentPromptCacheTtl with the worker answer and
    never promptCacheTtl".
26. G17-4. `no-poll-loops.sh` is unchanged: its limit follows each pane's own TTL. Test: no-poll-loops.test.sh "a
    relay pane at 1h may wait 540 s, a Builder at 5m only 270 s".
27. G17-5. The doctor and setup report print one prompt-cache line per role. Test: doctor.test.sh "the doctor names
    each role's prompt cache and where it is written" (after its timed cases).
28. G17-6. Setup recommends the owner's defaults and drops the 2026-10-18 main figure. Test: plugin.test.sh "option
    mainPromptCacheTtl defaults to setup's recommended answer (1h)".
29. G17-7 (revised in revision 1). The cache issue is issue 367 (open, filed 2026-10-25); the Closes line, batch
    brief and CHANGELOG name it. Test: none, a reference to an existing issue; `gh issue view 367` shows it open.
30. G18-1. The Stop hook is unregistered; its script and test stay. Test: plugin.test.sh "the Chief of Staff
    unfinished-work Stop hook is not registered, and its script stays executable".
31. G19-1. G19 is built only after the host commit lands on host main, and follows that commit. Revised in
    revision 5: "lands" means the host's unit merge commit (scope `(<unit>)`, not `docs(`) AND `REVIEW_CAP` and
    `passes_on_record` in host main's `.claude/scripts/builder-codex-pass.sh`; a plan-only commit is no gate. Test:
    none, a build-order gate the Builder runs (G19's gate command; `FAIL` on 2026-10-25 with `1b65d5bd` present) and
    main answers.
32. G19-2. The issue-325 KNOWN GAPS rule stays beside the threshold unless the host commit removes its equivalent.
    Test: builder-codex-pass-closing.test.sh, the existing KNOWN GAPS cases (:107-115) stay green.
33. G19-3. This unit's own passes run main's pass script (A1), so the threshold binds from the next unit and this
    unit's Done when keeps "every finding P0 to P3 blocks". Test: none, A1's command.
34. V-1. The README changes only where it states a removed or renamed option or flag (ponytail :117, :141, :257,
    :314; cache :118, :258-259; the Fable judge :111, :244-248), G19's review text, and the badge; the release README rewrite waits for the owner's
    order. Test: plugin.test.sh "the README's badge shows the manifest's version in its image and its alt text, on
    one line"; Claim 4's `rg`.
35. G10-6 (NEW in revision 1). The units mod reads the plugin's merges from `merge-unit-local.state`, the merge
    queue and `$PP_SCRATCH/merge-<unit>.log` (no `long-jobs` folder), by the six ordered rules of G10's adapter;
    running comes before a `FAILED` line in the log; the band lists running merges only. Revised in revision 3
    (replacing revision 2's log-mtime test): a state naming the unit decides its outcome (live: running; dead:
    stopped), and the log's `DONE` and `FAILED` count only when no state names the unit, since `release` removes the
    state on every way out of the attempt that wrote it. Revised in revision 4 (Decision G10-11): the log's `DONE`
    and `FAILED` are read from its newest attempt only. Test: units.test.tsx "a dead merge state beside a DONE log
    of the same second reads stopped, with no merge finished toast"; "a dead merge state over an hour old draws
    nothing, and a recent refusal in the log then shows"; "a live
    merge state names a running merge in the band and the pane"; "a merge whose pid died shows stopped in the pane
    and /units, and nothing in the band"; "a refusal shows its step and reason in the pane and /units, and nothing in
    the band"; "a live rerun beside an earlier refused log reads as running".
36. G17-8 (NEW in revision 1). `builder-cache-check.sh` proves the worker answer: 5m or 1h is the TTL both sides must
    write, unanswered is 5m, leave proves nothing and exits 0; revision 4: the answer is the worktree's own
    project's (`PP_MAIN` from `$WT`'s git common dir), not the caller's; also tested by "the check proves the
    worktree's own project's answer, not the caller's". Test: transcript-requests.test.sh "with
    workerPromptCacheTtl=1h a Builder and its subagents writing only 1h cache pass the check"; "with
    workerPromptCacheTtl=1h a main thread writing 5m cache fails the check"; "with workerPromptCacheTtl=leave the check
    proves nothing and exits 0 saying so".
37. G10-7 (NEW in revision 2). The shipped mod registers in a set-up Commandeck project (the main checkout has
    `.claude/commandeck.json`) and nowhere else, in place of the host's check for its host-local mod file. Test:
    units.test.tsx "a checkout with no Commandeck setup registers nothing"; "main and Chief of Staff default on, worker
    and reviewer default off: main" (a set-up project registers).
38. G10-8 (NEW in revision 2). The mod reads its views from `options.unitsBand`, `options.unitsPane`,
    `options.unitsStatus`, the manifest's keys, and `pp_option` answers the three for the doctor (`auto|on|off`,
    default `auto`). Test: units.test.tsx "unitsBand, unitsPane and unitsStatus off in config show no band, no pane and
    no status line in main"; plugin-option.test.sh "unitsBand, unitsPane and unitsStatus read auto by default, a
    /config off as off, and a value they do not take as auto".
39. G10-9 (NEW in revision 2). Test rows come from a live table the plugin's runner now writes
    (`<git dir>/commandeck-test-live/<pid>.tsv`, the host's format, removed at exit); the host's node and web test-log
    half is dropped; a table in a worktree outside `$PP_WORKSPACES` (the merge's copy) is skipped. Planning seats come
    from the seat records (`verdict=` done; no verdict and last phase not failed, running). Test:
    run-shell-tests.test.sh "a run's live table lists its files while they run and is gone when the run exits";
    units.test.tsx "a standalone run-shell-tests run shows files done and first failure in the pane and /units, and
    one test run in the band"; "a merge check's test lines show files done and the first failure in its merge row, and its tmp copy's
    table draws no test row"; "a planning unit shows its plan author done and its judges running from the seat
    records".
40. G16-4 (NEW in revision 2). The design check reads the pass commit's own tip (`SHA=` read right after the commit),
    before `rebase_and_test`; the existing `SHA=` after the rebase refreshes it. Test: builder-codex-pass-closing.test.sh
    "a design-only final reads its own commit before the rebase: run with SHA unset after a recorded first pass and
    a plan-only commit, it reads as design; run with SHA set to a code commit, it still reads as design".
41. G17-9 (NEW in revision 2). The legacy cache cases in install-lib.test.sh (:195-231) and doctor.test.sh
    (:115-147) are rewritten for the three roles; none is kept for the removed shared `promptCacheTtl`, and the
    replay harness fails loud when a setup line it extracts is gone. Test: install-lib.test.sh "il_cache_ttl never
    writes promptCacheTtl, and leaves an owner's own promptCacheTtl as it is"; "an old stored cacheTtl is no answer:
    nothing is written and the worker question is asked"; doctor.test.sh "with every answer Leave as is the doctor
    prints one leave line per role and no warn".
42. G20-1 (NEW in revision 2). The plugin's Fable judge names the family `fable`, which Claude Code resolves to
    `claude-fable-5-1`; the host's role names the id because host routing names ids. Test: plugin.test.sh "the Fable
    judge is a read-only Claude reviewer on fable at high, and no Astra judge role is left"; seat-launch.test.sh
    "plan-judge-fable launches Claude Fable at high with Write, Edit and NotebookEdit denied (its record says so)".
43. G20-2 (NEW in revision 2). The Astra judge role and its five options go (the plugin has no platform audit to keep
    it for); the Fable judge has four options and no agent key; no compatibility path for saved Astra answers (0 on
    this machine). Test: plugin.test.sh, the same case (no `plan-judge-astra` role, no `planJudgeAstra` reader);
    plan-tier.test.sh "Panel: the author and both judges, each on its agent and model".
44. G10-10 (NEW in revision 3). The runner's live table follows the host's selection pass: every selected file is
    listed before the first launch, a skipped one (parked, or own-lane without `--own-lane`) ends `skip 0` at once,
    and a file `--own-lane` excludes is never listed, so the table's total is the files this run decides on. Test:
    run-shell-tests.test.sh "a skipped own-lane file finishes as skip in the live table, and under --own-lane the
    ordinary file it leaves out never enters it".
45. G17-10 (NEW in revision 3). The relay writes its answer when it is 5m or 1h, by path, like the worker branch.
    Test: worktree-setup.test.sh "a relay answered 5m gets 5m, from a fresh settings file and beside another env
    entry".
46. G20-3 (NEW in revision 3). Every consumer of a removed Astra key is renamed, setup's fast-tier line and the
    GitHub launch test included, and a plugin test keeps setup's named keys inside the manifest. Test: plugin.test.sh
    "every option key setup's SKILL.md names is a manifest option"; `bash scripts/run-shell-tests.sh
    scripts/__tests__/seat-launch-github.test.sh` green.
47. G21-1 (NEW in revision 3). G21 is built only from the judged host plan once its judge says GO, ports the host
    commit's differences after the host merge, and is dropped if the host unit is not merged by 03:00 ET, on main's
    word, not the Builder's. Revised in revision 5: the host merge is the unit's merge commit (scope `(<unit>)`, not
    `docs(`) AND `.claude/scripts/post-fix-checks.sh` and the `test:post-fix` script on host main. Test: none, a
    build-order gate the Builder runs (G21's gate command; `FAIL` on 2026-10-25 with `cf1846ec` and `8b6ab6c4`
    present) and main answers.
48. G21-2 (NEW in revision 3). No check is removed or weakened: each hook G21 changes keeps its existing test with
    unchanged assertions, and the host plan's parity test is ported. Test: every changed hook's
    `hooks/__tests__/<hook>.test.sh` green unchanged; the parity test named from the judged host plan.
49. G10-11 (NEW in revision 4). Every merge attempt opens its output with one `ATTEMPT unit=<u> pid=<pid>
    started=<epoch>` line (`merge-unit-local.sh`, after the unit check :78, the lock holder only, not on a dry run);
    with no state for the unit the mod reads the log's newest attempt only (the last `ATTEMPT unit=<u> ` line to the
    end), and a log with no such line draws nothing; running file counts come only from an attempt whose `pid=` is
    the state's. Test: units.test.tsx "an earlier attempt's DONE in an appended log does not hide the newest
    attempt's refusal, in the same second or not"; "an earlier attempt's DONE followed by an unfinished attempt reads
    stopped, with no merge finished toast"; "a log with no ATTEMPT line draws nothing and toasts nothing"; merge-queue.test.sh
    "a unit queued twice appends one ATTEMPT line per attempt, the first attempt's step 1 refusal after its own".
50. G17-11 (NEW in revision 4). Leave writes nothing for main: setup's earlier TTL in main's settings file stays, with
    its record, while the file still holds setup's value; uninstall still takes it out. Test: install-lib-setup.test.sh
    "a /config answer of leave keeps the 1h setup wrote, and its record, a flag does not beat /config, and a /config
    5m then replaces it"; "a leave answer leaves an owner-changed TTL and drops setup's record". Revised in revision
    5: the answer is the effective one, `/config` first (`install-lib.sh:459-466`, unchanged), so both cases change
    `/config`, not only the flag.
51. G17-12 (NEW in revision 4). Each role's Needs-you line opens with its setup question's title, and the update skill
    matches the three titles and maps each to its flag. Test: plugin.test.sh "the update skill asks each role's
    prompt cache question from setup's text, with only that question's flag"; "each Needs-you prompt cache line opens
    with its setup question's title and names its flag".
52. G17-13 (NEW in revision 4). Every consumer of the old option names, flags, question text and the 5-minute check
    text is changed or named unchanged in G17's consumer list (`rg` over scripts, hooks, skills, docs, templates,
    config, README.md). Test: plugin.test.sh the three question checks and "no setup text says a 5-minute cache cost
    main less"; worktree-setup.test.sh "a worker and a Builder both get 5m (a Builder was 1h)" and "Leave as is writes
    no TTL anywhere" on `workerCacheTtl`; Claim 12's and Claim 17's `rg`.
53. G10-12 (NEW in revision 5). The ported `closesOf` reads a plan's first `Closes:` line in the plugin's form
    (`issue <n>`) and the host's (`#<n>`), and returns `#<n>` strings, so its caller is unchanged; a conditional
    `Closes (...):` line is not read. Test: units-sources.test.tsx "a plan's Closes line names its issues in the
    plugin's form and the host's".

## Accepted failure modes

1. A main started without `--settings .claude/main-session.settings.json` runs Claude Code's default cache; the
   doctor cannot see how main was started, so its main line names the start command. Test: doctor.test.sh "the
   doctor names each role's prompt cache and where it is written".
2. An install whose earlier setup wrote `promptCacheTtl: "5m"` into `.claude/settings.json` keeps it until uninstall
   or a hand edit (0 such installs here); main's `--settings` env value beats it (F-c). Test: none, count 0; the
   CHANGELOG names the key.
3. A rerun `final` with nothing new to commit after a design GO is read as a closing pass (the host's rule: no
   commit, no design); its reviewer reads the whole branch, so code the plan promises and the branch lacks is a
   finding. Test: builder-codex-pass-closing.test.sh "a final with nothing new to commit is read as a closing pass".
4. (Revision 2.) Test files the runner hands to the PC (0.47.0) show no live progress in the mod: the PC's runner
   writes its table in the PC's checkout, which the Mac's mod cannot read; the Mac's table lists only the files run
   here, and a run handed off whole writes none. The results still print in the runner's own output. Test: none for
   the hand-off itself (it needs the PC); run-shell-tests.test.sh "a run's live table lists its files while they run
   and is gone when the run exits" covers the local half.
5. (Revision 2.) A plan seat whose pane died before collect reads `running` in the mod until main reruns or collects
   it (the record has no verdict and no failed phase; the plugin's seats keep no live pid after dispatch). Test:
   units.test.tsx "a planning unit shows its plan author done and its judges running from the seat records".
6. (Revision 2.) An owner routing file (`COMMANDECK_ROUTING`) kept from before 0.48.0 keeps its own
   `plan-judge-astra` entry, read by nothing, beside the `plan-judge-fable` the next setup adds from the defaults; a
   saved `planJudgeAstra*` /config answer is read by nothing (0 of either on this machine). Test: none, count 0; the
   CHANGELOG names the keys.
7. (Revision 3; revised in revision 4.) While a merge runs, its file counts come only from the log's newest attempt
   whose `ATTEMPT` line's `pid=` is the state's `pid=` (revision 3's mtime rule, which could show an earlier
   same-second attempt's counts, is gone). A foreground rerun writes no log, so its row shows no counts until it ends
   (display only: its step is the state's `stage=`). Test: units.test.tsx "a live rerun beside an earlier refused
   log reads as running" (running, at the state's stage, no file counts).
8. (Revision 3.) A merge refused before it writes its state (step 1 preconditions, `merge-unit-local.sh:80-196`)
   beside an earlier killed attempt's state reads `stopped` until that state is an hour old, then `refused`. Test:
   units.test.tsx "a dead merge state over an hour old draws nothing, and a recent refusal in the log then shows".
9. (Revision 4.) A merge log written before 0.48.0 has no `ATTEMPT` line, so a merge that ended or was refused in
   the hour before the update shows no toast and no row (no state, no live queue entry). Reading such a log whole is
   what let an earlier `DONE` stand for a later attempt; drawing nothing is the safe side, and it lasts at most an
   hour per unit. Test: units.test.tsx "a log with no ATTEMPT line draws nothing and toasts nothing".
10. (Fix round 2.) Two one-plain-call adds of the same absent tmp path started in the same few milliseconds can
   both pass git's own path check and both exit 0 (git takes no lock there). The record step then needs the path
   named once by `git worktree list --porcelain`, so a second registration seen by either step grants nothing; a
   record step that runs before the slower git has registered its folder can still grant the first. Both sessions
   would have had to pick one tmp path at once (`mktemp` names differ), and the outcome is a worktree two gits
   checked out together. Test: none, it needs two gits inside git's own check window.
11. (Fix round 3.) The first readable poll of a session toasts no verdict, so a verdict that lands between the
   session start and that poll is shown in the row and the pane but not toasted. The alternative toasts every
   verdict already recorded each time a session starts. A unit that drops out of the snapshot's rows for a poll and
   comes back is new again, and its recorded verdict toasts once more. Test: units-sources.test.tsx "every verdict
   toast ordering found so far, in order" (its first and last steps).
12. (Fix round 4.) A worktree re-made at P by something that runs no PreToolUse hook (a person's shell, a script, a
   Codex pane), in the window between A's fenced add and A's record step, is still claimed by A: nothing replaced
   A's claim. So is one re-made by a hooked session in the milliseconds between A's record step reading the claim
   and writing the grant. Each needs a clean remove of A's new worktree and a re-add at the same tmp path inside that
   window (`mktemp` names differ). Test: none, the window is a few hook milliseconds or a hook queue's delay.

## 3. Assumptions (each settled, or a Builder check with the action per outcome)

- Settled: part A1 (`aa40679`) built G1-G4, G6, G7, G13, G14 and RD13's absence is real: `templates/_builder-brief-template.md:128`
  still reads "over 60 seconds" and `templates/main-session.md:7` has no test-run wording (read 2026-10-25).
- Settled: the worktree is removed at merge step 5 (`merge-unit-local.sh:160`) and `lines_changed` returns None then
  (`collect.py:486`).
- Settled: the host units mod on host main is `fdb79064`'s (`git log main -- .claude/units-mod`: c7aaf716,
  84118aa9, 8fb27eff, fdb79064); sizes 367/299/381/103 lines.
- Settled: host `24187ab2` removes only the registration (`.claude/settings.json`, 4 lines); the script stays.
- Settled: main's restart replays `--settings <path>` (`hooks/context-clear-stop.sh:173-180`).
- Settled: no saved prompt-cache answer on this machine (G17, commands and output above).
- A1, settled (main's ruling, carried): this unit's passes run the pass script from plugin main's checkout, so G16's
  and G19's gates bind from the next unit: `bash "$(git rev-parse --path-format=absolute --git-common-dir | sed
  's#/\.git$##')/scripts/builder-codex-pass.sh" plugin-remainder-2026-10-25 <N> adversarial|review|final`.
- A3, Builder check before G9: `jq '.units.inFlight[0] | keys'` on the fixture of `dashboard-alerts.test.sh` names a
  per-pass verdict list. Present: the alert reads it. Absent: `dashboard.sh` adds `newestPass {n, verdict, top}` to
  the unit object where the card reads round reports, and the alert reads that.
- A4, settled (revision 1, replacing the Builder check): the merge's state, queue and log are as G10's adapter lists
  them (`merge-unit-local.sh:56`, :79, :87-99, :186, :196; `paths.sh:481-491`, read 2026-10-25); merge rows read
  them through the adapter (Decision G10-6).
- A5, Builder check before G8's 358 part: `scripts/dashboard.sh:273`, `:285` read `$RUN/merge-shas` (unit, sha).
  Readable from `collect.py`: use it. Not: the squash commit is `git log main -1 --grep '^feat(<unit>)'`, and the
  comment says it is the fallback.
- A6, Builder check before G17: in a throwaway Claude session started with `claude --settings <file holding env
  CLAUDE_CODE_PROMPT_CACHE_TTL=1h> -p 'run: echo $CLAUDE_CODE_PROMPT_CACHE_TTL'`, the Bash tool prints `1h` (a hook
  sees the settings `env` the same way). Prints 1h: as planned. Prints nothing: main's value cannot reach a hook,
  which changes nothing for `no-poll-loops.sh` (it does not limit main); the Builder records it in the evidence file
  and G17 goes on.
  Catches: a G17 built on the belief that main's `--settings` env reaches main's own tools and hooks when it does
  not, so a later rule that reads main's TTL from its environment would read nothing.
- A7, Builder check before G10: in the mod engine, `fileURLToPath(new URL('..', import.meta.url))` inside
  `hooks/units.tsx` is the plugin root (a one-line probe in `hooks/units-sources.test.tsx`, or the engine's docs).
  Yes: `loadPaths` sources `<that root>/scripts/paths.sh` as planned. No: `loadPaths` builds the paths itself:
  `PP_SCRATCH` is `$COMMANDECK_SCRATCH` when set (read with `$.process.run(['printenv', 'COMMANDECK_SCRATCH'])`),
  else `$HOME/.commandeck/scratch/` plus the main checkout's path with every character outside `A-Za-z0-9` made `-`
  (`pp_slug`, `paths.sh:19`, :58, :62), and units-sources.test.tsx gains "the mod's scratch path matches paths.sh's
  for one checkout path". Either way the Builder records the answer in the evidence file.
  Catches: a mod whose `loadPaths` sources a `scripts/paths.sh` that is not there (the engine runs the module from
  somewhere other than the plugin's `hooks/`), so every view shows `units: paths unreadable` in every project.
  The same root serves `hooks/lib/project.sh` for the snapshot adapter's `PP_PROJECT` (revision 3); on "No",
  `loadPaths` derives it as `pp_project` does (the main checkout's folder name, every character outside
  `A-Za-z0-9_.-` made `-`, `hooks/lib/project.sh:16-19`).
- A8 (revision 3), Builder check before G21: the hook profile (G21's first bullet). Plugin Builder rows in the hook
  fire log: G21 picks changes by them. None: the Builder records that and ports only the host changes whose saving
  does not rest on the host's numbers.
  Catches: a G21 change picked by host numbers that saves nothing for the plugin's different hook set.

## 4. Dropped, done, not applying

- Item 4's parts already on main (G15 evidence list): `class_sites`, the Sites gate, the fix brief's Class sites,
  the template sentence, rg in the requirements, the class-sites test.
- RD8: in place (Decision RD-3).
- The host's `55126a9c` main-card trim and rule-file lines: no plugin site (the plugin's card is its own file; the
  rule is the template sentence).
- The host's typecheck skip and bugfix-lock message (`47632f56`): no plugin site (judged plan, Decision G4-4).

## 5. Build order and size (changed lines, code + tests, estimates)

| Order | Group | Items | ~Lines |
|--:|---|---|--:|
| 0 | Builder checks A3, A5-A7 (minutes) | | 0 |
| 1 | G18 | item 7 | 10 |
| 2 | G5 | 359 (~95), 365 (~360 with the README and NOTICE rows) | 455 |
| 3 | G8 | 356 (~45), 357 (~105), 358 (~50) | 200 |
| 4 | G9 | 364 part 2 (~45), 360 (~110) | 155 |
| 5 | G12 (halfway note after it) | RD1-RD13 less RD8 (RD6 restored, +2) | 187 |
| 6 | G20 | item 8, the Fable judge: routing, options, readers, text (~47) and the nine test files (~80, the setup-key check and the GitHub launch test in revision 3; the doctor's Claude group in revision 4, ~2) | 129 |
| 7 | G15 | item 4 | 10 |
| 8 | G16 | item 5, with the class-return test, the design finish wording and the SHA order (~5) | 105 |
| 9 | G17 | item 3, with the cache checker (~45), doctor-options (~10), the legacy cache tests (~85) and the relay 5m case (~10); revision 4: the leave branch and its two cases (~35), the checker's project read and its case (~25), the update skill, Needs-you titles and plugin.test.sh checks (~25), the sibling fixtures, README row, doc and comments (~15); revision 5: the /config replay steps (~10) | 550 |
| 10 | G10 | 349 (~1,190 ported), the merge-state adapter (~100 with its tests), the merge gate (~70 with its tests), the activation guard and option readers (~35 with tests), the runner's live table and the test and seat sources (~115 with tests), revision 3: the snapshot adapter (~40 with tests), the live table's selection pass (~30 with tests), the state-first merge rules (~15); revision 4: the attempt marker and newest-attempt slice (~15), the merge table's fixture edits and five new cases (~60), the producer case (~20); revision 5: the Closes parser and its case (~10) | 1700 |
| 11 | G11 | 348 | 190 |
| 12 | G19 (gated) | 366 | 450 |
| 13 | G21 (gated, last group; dropped on main's word if the host unit is not merged by 03:00 ET) | item 9 | 250 |
| 14 | version, CHANGELOG, README badge | | 70 |
| | Total | | ~4,461 (~4,211 without G21) |

Files shared between groups, in build order:
- `scripts/builder-codex-pass.sh`: G5 (`plan_section`, `CLAIMS`) -> G8 (`Pre-review:` line) -> G12 (`LIMITS_HEAD`,
  `FORMAT`, `GUIDANCE`) -> G15 (`FORMAT`) -> G16 (design heads and `--verify`) -> G19 -> G21 (fix-brief verify text).
- `templates/_builder-brief-template.md`: G5 (`{ponytail}` :26, the cut-pair table) -> G12 (How to work, :128-129)
  -> G19 -> G21 (:94-105, the post-fix checks).
- `scripts/paths.sh`: G5 (`ponytail` :1143, :1162) -> G17 (:1146) -> G10 (units cases beside :1150, :1164).
- `scripts/setup.sh`: G5 (ponytail lines) -> G20 (:268) -> G17 (cache lines).
- `.claude-plugin/plugin.json`: G5 (-`ponytail`) -> G12 (RD4 descriptions) -> G20 (Astra keys out, Fable keys in,
  :128) -> G17 (cache options) -> G10 (+3 units options) -> version.
- `config/routing.json`: G12 (RD4 `roles.fixer.first`) -> G20 (the judge role).
- `scripts/install-lib.sh`: G5 (`IL_MAIN_LEAN` ponytail keys) -> G17 (`il_main_lean` TTL, `il_cache_ttl`, report).
- `scripts/worktree-setup.sh`: G5 -> G17. `hooks/hooks.json`: G18 -> G8 -> G10 -> G21. `docs/hooks.md`: G18 -> G8.
  `scripts/merge-unit-local.sh`: G10 -> G19. `scripts/__tests__/plugin.test.sh`: G18 -> G5 -> G20 -> G17 -> G10.
- `README.md`, `skills/setup/SKILL.md`, `docs/configuration.md`, `templates/main-session.md`: G5 -> G12 -> G20 -> G17.
  `scripts/__tests__/install-lib-setup.test.sh`: G5 -> G12 -> G20 -> G17. `plugin-option.test.sh`: G5 -> G20 -> G17
  -> G10.
  `scripts/__tests__/doctor.test.sh`: G20 (:213-224) -> G17 (:115-147 and the new case after the timed ones).

The whole unit is over the plugin's caps (40 files, 3,000 review lines, `config/routing.json:101`, a note no script
enforces); the owner's order keeps it one unit. The pass script falls back to a context-free diff above
`DIFF_MAX` (400,000 characters, `builder-codex-pass.sh:180`, `:1125`), as part A1's passes did.

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| foreign path | session A owns a tmp worktree with an uncommitted file; session B runs `git worktree add <that path> HEAD` (fails), then `git worktree remove --force <that path>` | B's remove is blocked; A's worktree and file remain | git-safety.test.sh "session B's failed add on session A's worktree path, then B's forced remove: blocked, A's worktree and its uncommitted file still there" |
| old shape (worktree) | a worktree set up before 0.48.0: the summary SessionStart hook, its off leaf, and an owner hook in the same registration | the rerun drops setup's hook and off leaf and keeps the owner's hook; the script runs with `templates/ponytail/` gone | worktree-setup.test.sh "a rerun on a worktree set up with the summary hook drops that hook and its off leaf and keeps an owner hook beside it" |
| odd data (owner's TTL) | `.claude/main-session.settings.json` already holds the owner's `env.CLAUDE_CODE_PROMPT_CACHE_TTL` 5m; main answered 1h | the owner's value stays, setup names it; the doctor's main line warns it is not 1h | install-lib-setup.test.sh "an owner's TTL in main's settings file stays, and setup names it" |
| rerun (answer changes) | setup ran with main 1h (prefilling /config); /config then leave, rerun; then /config 5m, rerun; then uninstall | leave keeps setup's 1h and its record; 5m replaces it; uninstall takes it out; nothing appears in main's settings.local.json or settings.json | install-lib-setup.test.sh "a /config answer of leave keeps the 1h setup wrote, and its record, a flag does not beat /config, and a /config 5m then replaces it" |
| odd data (flag against /config) | /config holds leave; `setup.sh --main-cache-ttl 5m` | TTL and record stay 1h; `note: mainPromptCacheTtl is leave in /config, which beats this answer (5m)` | install-lib-setup.test.sh "a /config answer of leave keeps the 1h setup wrote, and its record, a flag does not beat /config, and a /config 5m then replaces it" (step 3) |
| odd data (owner changed setup's TTL) | setup wrote main 1h; the owner edited it to 5m and set /config to leave; rerun with leave | the file keeps 5m, setup's record drops the TTL, no note | install-lib-setup.test.sh "a leave answer leaves an owner-changed TTL and drops setup's record" |
| leak (shared file) | the main checkout's `settings.local.json` sets `CLAUDE_CODE_PROMPT_CACHE_TTL=1h`; workers answered 5m | the doctor warns that the file overrides every worktree, naming the file | doctor.test.sh "a TTL in main's settings.local.json is warned as overriding every worktree" |
| limits (wait budget per role) | a relay pane (Chief-of-Staff worktree) at 1h runs a 540 s and a 600 s ask; a Builder at 5m runs a 300 s ask | relay: 540 passes, 600 refused; Builder: refused | no-poll-loops.test.sh "a relay pane at 1h may wait 540 s, a Builder at 5m only 270 s" |
| odd data (design commit) | a final whose commit holds the plan and a `.claude/metrics` row; then one whose commit adds a script too | the first reads as design-only, the second as a closing pass | builder-codex-pass-closing.test.sh "a commit of the plan and the ledger is design-only; one more script makes it a closing pass" |
| empty (design rerun) | after a design GO, `final` again with nothing to commit | read as a closing pass (Accepted failure mode 3) | builder-codex-pass-closing.test.sh "a final with nothing new to commit is read as a closing pass" |
| not a plugin | a project with no `.claude-plugin/plugin.json` merges a unit that changed `hooks/x.ts` | no `claude plugin test` runs; the merge goes on | merge-unit-local.test.sh "a project that is not a plugin, with a changed hooks/x.ts, runs no claude plugin test" |
| no check command (plugin gate) | a plugin unit changing `hooks/x.ts`; `.claude/commandeck.json` has no `testCommand` | `STEP 4 plugin` runs `claude plugin validate .` and `claude plugin test .` on a copy of the merged tree | merge-unit-local.test.sh "a plugin unit changing hooks/x.ts with no testCommand runs claude plugin validate and test on the merged tree" |
| reused proof (plugin gate) | the same unit, the closing pass's green `Suite proof:` matching the merged tree | the check is reused and the plugin gate still runs | merge-queue.test.sh "a merge that reuses the closing pass's green suite still runs claude plugin test on a plugin unit" |
| red mod test | `claude plugin test .` exits 1 on the merged tree | `FAILED step 4 plugin`, exit 1, main's HEAD unchanged, nothing staged | merge-unit-local.test.sh "a red claude plugin test refuses the merge and leaves main where it was" |
| timing (merge pid dies) | `merge-unit-local.state` names unit `u`, `log=$PP_SCRATCH/merge-u.log`, no `long-jobs` folder; then the pid dies | first running in band and pane; then stopped in the pane and `/units`, nothing in the band | units.test.tsx "a live merge state names a running merge in the band and the pane"; "a merge whose pid died shows stopped in the pane and /units, and nothing in the band" |
| odd data (refusal, stale log) | no state; the log ends `FAILED step 3 record: review ledger has no GO`; later a foreground rerun of `u` is live while that log remains | refused with step and reason, not in the band; then running | units.test.tsx "a refusal shows its step and reason in the pane and /units, and nothing in the band"; "a live rerun beside an earlier refused log reads as running" |
| 1h Builder cache | `workerPromptCacheTtl=1h`; main and subagent transcripts hold only `ephemeral_1h_input_tokens` | `builder-cache-check.sh "$WT" "$SESSION"` exits 0; a 5m main thread fails | transcript-requests.test.sh "with workerPromptCacheTtl=1h a Builder and its subagents writing only 1h cache pass the check"; "with workerPromptCacheTtl=1h a main thread writing 5m cache fails the check" |
| narrowed vs design finish | `Pass: review`, `VERDICT: GO`, DONE; and `Pass: design`, `VERDICT: GO`, DONE | the first posts "Finished on a narrowed pass", the second "Finished on a design-only pass"; neither merges | main-watch-report-wake.test.sh (narrowed case :47-55); "a DONE after a design GO is posted as finished on a design-only pass, not as narrowed, and is not merged" |
| unregistered hook | `hooks/hooks.json` after G18 | no Stop entry names the script; the script is executable; the fire-log guard passes | plugin.test.sh "the Chief of Staff unfinished-work Stop hook is not registered, and its script stays executable" |
| odd data (design pass, no SHA) | a recorded first pass, then a plan-only commit; `env -u SHA bash scripts/builder-codex-pass.sh u 2 final`, and again with `SHA` set to a code commit | each reads as design: `Pass: design`, the review under `HEAD_DESIGN`; no unbound-variable exit | builder-codex-pass-closing.test.sh "a design-only final reads its own commit before the rebase: run with SHA unset after a recorded first pass and a plan-only commit, it reads as design; run with SHA set to a code commit, it still reads as design" |
| odd data (plain project) | a session in a git checkout whose main has no `.claude/commandeck.json` | the mod registers no command, opens no pane, sets no status, runs no `bash` | units.test.tsx "a checkout with no Commandeck setup registers nothing" |
| odd data (views off) | `{"unitsBand":"off","unitsPane":"off","unitsStatus":"off"}` in /config, main seat, one live unit | no band row, no pane, no status line; the doctor lists the three as `off (from /config)` | units.test.tsx "unitsBand, unitsPane and unitsStatus off in config show no band, no pane and no status line in main"; plugin-option.test.sh "unitsBand, unitsPane and unitsStatus read auto by default, a /config off as off, and a value they do not take as auto" |
| timing (standalone tests) | `bash scripts/run-shell-tests.sh scripts/__tests__/plugin.test.sh` running in worktree `u` while `/units` is open; no merge | a `shell` test row for `u` with files done and elapsed in the pane and `/units`; the band says `▸ 1 test run`; the table is gone after the run | run-shell-tests.test.sh "a run's live table lists its files while they run and is gone when the run exits"; units.test.tsx "a standalone run-shell-tests run shows files done and first failure in the pane and /units, and one test run in the band" |
| odd data (plugin Closes line) | a planning unit's plan with `Closes: issue 348, issue 349`; and one with `Closes: issue 348` then `Closes (only when G19 is built): issue 366` | `#` plus 348 and 349; then `#` plus 348 only | units-sources.test.tsx "a plan's Closes line names its issues in the plugin's form and the host's" |
| timing (stale DONE, same second) | state `unit=u`, `started=200`, dead pid, mtime 200,000 ms; `merge-u.log` mtime 200,000 ms ending `DONE unit=u`; clock 201,000 ms | stopped in the pane and `/units`; no `merge finished` toast; nothing in the band | units.test.tsx "a dead merge state beside a DONE log of the same second reads stopped, with no merge finished toast" |
| timing (old dead state) | a killed attempt's state for `u`, 3,601 s old; a newer refusal, `FAILED step 1 preconditions: x`, in a 10 s old log | `refused at step 1 preconditions: x` | units.test.tsx "a dead merge state over an hour old draws nothing, and a recent refusal in the log then shows" |
| odd data (plugin snapshot) | the judge's `data.js`: `projects.p.units` with one in-flight unit and `mergedSincePush[{unit: v, at}]`; and the same for a project `q` it does not hold | `u` building, `v` merged at 19:00Z; for `q` the note `units: this project is not in the dashboard snapshot` | units-sources.test.tsx "a plugin snapshot's project units, merge times and costs parse"; "a snapshot without this project, or with no unit list, draws nothing and says why" |
| limits (live table total) | one ordinary and one `# own-lane:` file; then the same pair under `--own-lane` | first: both listed, the own-lane file ends `skip` before any start; second: only the own-lane file listed | run-shell-tests.test.sh "a skipped own-lane file finishes as skip in the live table, and under --own-lane the ordinary file it leaves out never enters it" |
| odd data (relay 5m) | Chief-of-Staff `settings.local.json` `{}`, then `{"env":{"OTHER":"x"}}`; `relayPromptCacheTtl=5m` | `env.CLAUDE_CODE_PROMPT_CACHE_TTL` `5m` both times; `OTHER` kept | worktree-setup.test.sh "a relay answered 5m gets 5m, from a fresh settings file and beside another env entry" |
| removed key (setup answer) | setup's fast-tier answer "Judges" after G20 | `planJudgeSolFast` and `planJudgeFableFast` sent; no key the manifest lacks | plugin.test.sh "every option key setup's SKILL.md names is a manifest option" |
| odd data (merge copy tests) | a live merge whose check runs the suite in its tmp copy, the copy's runner writing a live table | the merge row counts the files; no separate test row for the copy | units.test.tsx "a merge check's test lines show files done and the first failure in its merge row, and its tmp copy's table draws no test row" |
| limits (judge stays read-only) | a Panel plan; `seat.sh launch plan-judge-fable <unit> <spec>` | Claude Fable at high with `--disallowedTools Write,Edit,NotebookEdit`; no Astra seat is planned | seat-launch.test.sh "plan-judge-fable launches Claude Fable at high with Write, Edit and NotebookEdit denied (its record says so)"; plan-tier.test.sh "Panel: the author and both judges, each on its agent and model" |
| odd data (appended log, earlier DONE) | no state or queue entry; `merge-u.log` 10 s old holding `ATTEMPT unit=u pid=7 started=200`, `DONE unit=u`, `ATTEMPT unit=u pid=8 started=200`, `STEP 1 preconditions: retry`, `FAILED step 3 record: review ledger has no GO` | `refused at step 3 record: review ledger has no GO`; no `merge finished` toast; nothing in the band | units.test.tsx "an earlier attempt's DONE in an appended log does not hide the newest attempt's refusal, in the same second or not" |
| timing (appended log, newest unfinished) | the same log with the second attempt ending at `STEP 2 rebase: y` | `stopped` at `2 rebase`, no toast | units.test.tsx "an earlier attempt's DONE followed by an unfinished attempt reads stopped, with no merge finished toast" |
| old shape (log before 0.48.0) | no state; a 10 s old log `STEP 1 preconditions: y`, `DONE unit=u`, no `ATTEMPT` line | nothing drawn, no toast (Accepted failure mode 9) | units.test.tsx "a log with no ATTEMPT line draws nothing and toasts nothing" |
| limits (attempt marker, refusal before STEP 1) | `merge-queue.sh u` refused at step 1 (no worktree), then the worktree made and `merge-queue.sh u` again | the log holds two `ATTEMPT unit=u` lines, the `FAILED step 1 preconditions` line between them, `DONE unit=u` after the second | merge-queue.test.sh "a unit queued twice appends one ATTEMPT line per attempt, the first attempt's step 1 refusal after its own" |
| odd data (checker run from another project) | from project A (`workerCacheTtl` 5m) run `builder-cache-check.sh` on project B's worktree (B `workerCacheTtl` 1h, no /config answer), both transcripts 1h-only | exit 0 (B's 1h is proved) | transcript-requests.test.sh "the check proves the worktree's own project's answer, not the caller's" |
| removed text (update asks the new questions) | update's Needs you lists `Main prompt cache: not answered since 0.48.0 ...` and `Builder and worker prompt cache: ...` | the update skill names both titles and their flags; setup's Needs-you lines open with the titles | plugin.test.sh "the update skill asks each role's prompt cache question from setup's text, with only that question's flag"; "each Needs-you prompt cache line opens with its setup question's title and names its flag" |
| old key in a fixture (worker answer) | worktree-setup.test.sh's project config `{"workerCacheTtl": "5m"}`, then `"leave"` | a worker and a Builder get 5m; then no TTL anywhere | worktree-setup.test.sh "a worker and a Builder both get 5m (a Builder was 1h)"; "Leave as is writes no TTL anywhere" |
| skipped pass number (G19) | the third pass on record launched as `... 9 review` with a P2 | not at the cap: runs narrowed, no stop, merge refuses | builder-codex-pass-threshold.test.sh "the pass number is not the count" |
| severity lowered (G19) | pass 5's record has `[P1]`, the round file edited to `[P3]` | `--verify` still refuses; no stop printed | builder-codex-pass-threshold.test.sh "a severity lowered in the round file changes nothing" |
| filing missing or closed (G19) | `--filed` absent; names a closed issue; names a class not open; gh exits 1 | refused each time, naming the class or gh's error | builder-codex-pass-threshold.test.sh "a filed issue must be open" |
| one check hangs (G21) | the mods stub sleeps 60, cap 2 s | `mods timed out after 2s`, the other two exit 0, exit 1, ends in under 20 s | post-fix-checks.test.sh "a hung check is cut off at the cap and named" |
| run killed (G21) | TERM to the runner while the stubs sleep | no stub alive after 15 s, exit non-zero, logs kept, no green line | post-fix-checks.test.sh "a killed run leaves no check running" |
| two fail, different codes (G21) | shell 0, validate 2, mods 3 | each line its own code, both red tails printed, exit 1 | post-fix-checks.test.sh "two failures keep their own codes" |
| early failure, later successes (G21) | shell 2, validate 0, mods 0 | `post-fix: shell exit 2`, `post-fix: 1 of 3 failed: shell`, no green line, exit 1 | post-fix-checks.test.sh "an early failure survives later successes" |
| not a plugin, no files (G21) | a checkout with no `.claude-plugin/plugin.json`; no test files named | nothing started: exit 2, says why | post-fix-checks.test.sh "a checkout with nothing to check exits 2" |
| planning cost (G10, pass 2) | an in-flight unit with `builder: null` and `plan.cost.stages` `[{planning, 4}]`; then one with a Builder cost | the row and today's spend read 4; with a Builder, only the Builder's cost | units-sources.test.tsx "a planning unit's spend counts before the Builder starts" |
| verdict first seen (G10, passes 2-3; third return, redesigned) | one poll sequence of `Seen` states: the session's first poll (`prevSeen` null) with u `1:GO`; the same again; w first seen with `2:NO-GO`; the same again; u now `3:GO`; x first seen with `1:` (no verdict), then x `1:GO`; `prevSeen` reset to null (session start), then w `3:GO` | no toast; none; `w: verdict 2 NO-GO` once; none; `u: verdict 3 GO`; none, then `x: verdict 1 GO`; the poll after the reset toasts nothing, the one after it toasts as before | units-sources.test.tsx "every verdict toast ordering found so far, in order" |
| stop answered by the route (G19, pass 4) | pass 7 holds a P1 (`REVIEW STOP`, decision `review-stop-p1-r7`); the Builder runs the printed `ask-main.sh "review-stop-p1-r7: <class>"`, orca-wait.sh records it as `p1-msg_<id>` and answer-worker.sh answers that row; then the next pass launches | the launch runs: a ledger row answers the stop when its id is the stop id or its question opens with `<stop id>:` | builder-codex-pass-threshold.test.sh "with r7 answered through ask-main.sh and answer-worker.sh the next pass runs; ..." |
| backfill push failed (G11, pass 2) | a local `v0.1.0` whose push failed; origin lacks it; no releases | the rerun pushes every missing tag, then each `--verify-tag` release is made | release-notes.test.sh "a local tag whose push failed is pushed by the rerun before the release is made" |
| relative path (G8, pass 1) | a session owns `<cwd>/w`; then `git -C <other checkout> worktree remove --force w`, and `cd <other> && git worktree remove --force w` | both blocked: only an absolute or `~/` path is ever owned | git-safety.test.sh "a relative path after -C or cd is never owned: both forced removes block" |
| reused path (G8, pass 1) | A adds and removes a tmp worktree at P; B adds a new one at P; A, then B, run a forced remove of P | A blocked (the grant went with A's worktree), B allowed | git-safety.test.sh "every ownership ordering found so far, in order" (step 1) |
| failed add, path held (G8, pass 1) | A's add of Q failed; B's worktree now holds Q; A runs a forced remove of Q | blocked: a failed add fires no PostToolUse and grants nothing | git-safety.test.sh "every ownership ordering found so far, in order" (step 2) |
| concurrent adds, masked failure (G8, pass 2) | A's and B's PreToolUse both see P absent (A's chained add is off the fixed list, so only B writes a claim); B adds P; A's `git worktree add P HEAD; true` fails but exits 0; A's PostToolUse runs before B's; B writes a file in P; A, then B, run a forced remove of P | A blocked (a chained add grants nothing); B's add was one plain call, so B is allowed; B's file is kept by A's block | git-safety.test.sh "every ownership ordering found so far, in order" (step 3) |
| chained remove (G8, pass 2 sweep) | A owns P; A runs `git worktree list; git worktree remove --force P` (any call before or after the remove) | blocked: only a one-plain-call forced remove uses a grant, so nothing runs between the check and the remove | git-safety.test.sh "every ownership ordering found so far, in order" (step 4) |
| lost grant, retry (G8, pass 2) | A added P with one plain call; P's `commandeck-owner` (the one piece of ownership state) is deleted between the add and the remove | A's forced remove is blocked and names `git worktree remove <path>`; that plain remove is not blocked and git removes the clean worktree | git-safety.test.sh "every ownership ordering found so far, in order" (step 5) |
| delayed record step (G8, pass 4) | A's fenced add of P succeeds (its PreToolUse wrote A's claim); before A's PostToolUse, the clean worktree is removed, B's PreToolUse (claim now B) and add re-make P and B writes a file in P; then A's record step, then B's; A, then B, run a forced remove of P | A blocked (the claim names B, so A's late record step grants nothing); B allowed; B's file is kept by A's block | git-safety.test.sh "every ownership ordering found so far, in order" (step 6) |
| an add that adds nothing (G8, pass 4 sweep) | B's worktree at P has no grant (B's add was chained); A runs `git --version worktree add P HEAD` (exit 0, nothing added) through PreToolUse and PostToolUse; A runs a forced remove of P | blocked: `--version` is off the fixed list, so no claim and no grant | git-safety.test.sh "every ownership ordering found so far, in order" (step 7) |
| lost claim, retry (G8, pass 4) | A's fenced add of P: its claim is deleted between its PreToolUse and its record step | no grant; A's forced remove is blocked and names `git worktree remove <path>`; that plain remove removes the clean worktree | git-safety.test.sh "every ownership ordering found so far, in order" (step 8) |
| abbreviated long option (G8, pass 5 sweep) | `git worktree remove --forc P` (`--f`, `--fo`), and the same for the other discard checks: `checkout --forc`, `switch --disc`, `clean --forc`, `branch --del --forc`, `gc --pru=now`, `restore --staged --work`, `reset --har` | blocked: git takes any unambiguous prefix of a long option, so each check reads every prefix of its option (`abbr`); a forced remove that uses a grant must still spell `-f` or `--force` | git-safety.test.sh "blocks: git worktree remove --forc /tmp/wt" and the six beside it |
| reworded global rule (G19, G5; closing run after pass 6) | an owner kept their own wording of a global rule (`--drop 13e9906d`, or of `c8e23316` before it); this build rewords it (26b6b2b9), and five others in global-rules.md | the reworded rule stays out for that owner and loads again with `--keep <new id>`: each new id has its `MADE_FROM` line in scripts/merge-rules.py | merge-rules.test.sh "reworded global <new>: in by default, out under keep mine of <old>, in again with --keep <new>" (six pairs) and "reworded 26b6b2b9: ... c8e23316 ..." |
| checkout under -C (G8, pass 1) | `git -C <dir> checkout <a file only that folder has>` | blocked: the one-word lookup is made where git runs | git-safety.test.sh "git -C <dir> checkout <a file only that folder has> blocks" |
| publish failed after tag (G11, pass 1) | a run pushed tag v1.1.0, then Publish failed; the job reruns | the decision is `release v1.1.0`; the Tag step finds its tag, exits 0 and pushes nothing; a version whose tag and release exist decides skip | release-notes.test.sh "a tag pushed by a run whose publish failed decides release again"; "a rerun's Tag step with its tag already there exits 0 and pushes nothing"; "a changed version whose tag and release exist decides skip" |
| decide fails (G11, pass 1) | the Decide step's script exits 1 (version unreadable) | the step fails and writes no `decision=` line | release-notes.test.sh "a Decide step whose version cannot be read fails, writing no decision" |
| idle pane (G10, pass 1) | `unitsPane` on, no live unit; then a unit goes live; then it finishes | no pane opened; the pane opens; the pane closes | units-panes.test.tsx "no live units: no band row, no pane, no status line"; "the pane opens when a unit goes live and closes when the last one finishes" |
| shared status line (G10, pass 1) | the relay seat with auto-decide off and one unit building, over two polls | `1 building · today $1.00 · auto-decide off` both times | units.test.tsx "the relay keeps its units summary beside the auto-decide mode, across polls" |
| merged then pushed (G10, pass 1) | a snapshot whose `mergedSincePush` is empty after a push and whose `finishedBuilds` holds today's merge with its cost | the merge row and today's spend stay | units-sources.test.tsx "a push keeps today's merged builds and their spend" |
| built beyond the brief (G10, pass 7) | a building unit with `issues:[349]`, `built:[349,357]` (an evidence heading also names 357); and `issues:[349,"Rule drift"]`, `built:["Rule drift",357,"Rule drift","other"]` | `██████████  1 of 1 issues built`, no RangeError; then `█████░░░░░  1 of 2 issues built`: only the brief's issues count (as `dashboard/app.js` counts) and the bar stays 10 wide | units-sources.test.tsx "issues built count only the brief's issues, and the bar never overflows" |
| main-only scope (G9, pass 1) | a project with no relay pane | main's loaded rules carry the order file, the NOT-ordered additions, one multi-select question, no bundle approvals, the pass-4 report; the plan author writes an `Owner's words:` line and the judge flags an untraced requirement | agent-startup-context.test.sh "with no relay pane main keeps the scope rules: the order file, NOT-ordered additions checked, one multi-select question, no bundle approvals, pass 4 reported"; seat-plan-marker.test.sh "a plan-author's prompt asks for the Owner's words line from the order, every requirement traced to it"; "the judge's prompt makes a requirement that does not trace to the owner's words a finding (issue 360)" |
| pass-4 warning (G9, pass 1) | a fourth NO-GO with no class stop | the relay (and main with no relay) tells the owner at pass 4 | agent-startup-context.test.sh "the relay's scope rules: owner's words only, NOT-ordered additions checked by cos-order-check.sh, one multi-select picker, no bundle approvals, pass 4 reported" |
| state not in Data design (pass 1) | the live test table, the units atoms and caches, the status-line parts, the setup records, the pass kind line, the worktree grant | each is named with its writer, reader, reset and retry in the brief's Data design | the review pass's data-design check (`DATA_DESIGN` in `builder-codex-pass.sh`); no unit test reads the brief |

## Claims to falsify

1. After G5 nothing reads `pp_option ponytail`, `{ponytail}` or `templates/ponytail/` (`rg -n -i --hidden ponytail
   scripts hooks templates .claude-plugin config docs skills README.md NOTICE` shows only old comment tags,
   `config/retired.tsv`, the summary-hook cleanup's match and the relay's off removal in `worktree-setup.sh`, and
   fixtures naming the third-party plugin); `bash scripts/worktree-setup.sh "$WT" --builder` succeeds with
   `templates/ponytail/` gone.
2. Main's TTL is in no file a worktree reads: after setup, `.claude/settings.json` and the main checkout's
   `settings.local.json` hold no `CLAUDE_CODE_PROMPT_CACHE_TTL` and no `promptCacheTtl`.
3. Main's restart keeps its `--settings` file, so its TTL survives a restart (`context-clear-stop.sh:173-180`).
4. After G18 no `hooks/hooks.json` entry names `cos-unfinished-stop.sh`, and every hook guard stays green.
5. A design-only GO never merges: `--verify` refuses it, and main-watch never says "merge" for it, and never calls
   it narrowed.
6. The units mod writes no file and reads no stall field; its band never lists a stopped or refused merge; it reads
   no `long-jobs` path (`rg -n long-jobs hooks/units*.ts*` is empty), no host product path or name (`bash ci/leak-test.sh`
   passes on them) and no `options.band`, `options.pane` or `options.status` (revision 2); it registers in
   a set-up project and in no other checkout.
13. (Revision 2.) While `run-shell-tests.sh` runs, `<git dir>/commandeck-test-live/<its pid>.tsv` exists and lists
    every file it runs here; after it exits, by any way out the EXIT trap sees, the file is gone.
14. (Revision 2.) After G20, `rg -n -i 'planJudgeAstra|plan-judge-astra' scripts hooks config templates skills docs
    README.md .claude-plugin -g '!**/__tests__/**'` is empty (revision 3: `skills/setup/SKILL.md:161`'s
    `planJudgeAstraFast` included), and a Panel plans `plan-author plan-judge-fable plan-judge-sol`, the Fable seat
    launching with Write, Edit and NotebookEdit denied; `rg -n 'plan-judge-astra|planJudgeAstra' scripts/__tests__`
    matches no launch, cap or role loop (data-only seat records, G20's "Not changed" list, excepted).
15. (Revision 3.) The units mod reads a real plugin `data.js`: for the project the mod runs in, its in-flight units
    and today's merges show; no read of a top-level `units` or of `mergedAt` is left in `hooks/units*.ts*`
    (`rg -n 'j\.units|mergedAt' hooks/units-sources.ts` shows only the `Snap` field `mergedAt` and its assignment).
16. (Revision 3; widened in revision 4.) The log's `DONE` never toasts "merge finished" while a recent state names
    the unit, whatever the two files' mtimes, nor when a later `ATTEMPT unit=<u>` line follows it in the log; and
    `hooks/units.tsx` passes `parseMergeLog` no line before the log's last `ATTEMPT unit=<u> ` line.
17. (Revision 4.) After G17 no shipped file or test names a removed cache key, flag or question: `rg -n
    '"cacheTtl"|\bcacheTtl\b|promptCacheTtl\b|--cache-ttl|Ask "Prompt cache"|Ask "Relay prompt cache"|Relay prompt
    cache:' scripts hooks skills docs templates config README.md` matches only `chiefOfStaff.cacheTtl` reads and
    the test fixtures' `"chiefOfStaff": {..., "cacheTtl": ...}`,
    `subagentPromptCacheTtl`, `relayPromptCacheTtl`, `mainPromptCacheTtl`, `workerPromptCacheTtl`, the
    `config/retired.tsv` row, G17's "never writes promptCacheTtl" and settings.json absence checks,
    install-lib.test.sh's "an old stored cacheTtl is no answer" fixture, and (revision 5, exempt) the manifest's
    ownership records `.entries[$p].cacheTtl` in `scripts/install-lib.sh` (`il_cache_ttl` :279-288: what setup wrote
    to `.claude/settings.json`, read back by a rerun and by uninstall's unchanged `off` path). Those records are not
    a removed key: the Builder neither renames nor removes them to satisfy this search, and `rg -n '\bcacheTtl\b'
    scripts/install-lib.sh` showing :279, :282, :284 and :288 is a pass.
11. Every merge path of a plugin unit that changes `hooks/*.ts`, `hooks/*.tsx` or `types/` runs `claude plugin
    validate .` and `claude plugin test .` on the merged tree: no `testCommand`, a run check and a reused suite proof.
12. `builder-cache-check.sh` passes a Builder answered 1h whose transcripts hold only 1h writes, whichever project
    it is run from, and nothing in the plugin requires 5m when the worker answer is 1h (`rg -n "only 5m|only
    5-minute|5-minute prompt cache" scripts docs` is empty; revision 4 added `docs` and the two phrases).
7. `release-decide.sh` says skip when the version did not change or its tag and release both exist, and the
   workflow runs no tag or publish step without its `release` output.
8. `git-safety.sh` blocks every forced remove of a path the session's own successful add on an absent path did not
   create, a failed add on another session's path included.
9. The plugin's `FORMAT` asks for a Class search line under blocking findings only; a KNOWN GAPS line carries none.
10. Every RD item's text is in its target file, and no host-only name (repo id, host paths, machine figures) is.

## Contracts (Produces / Consumes across groups)

- G5 `plan_section <heading>`. Produces: the lines under a plan heading (`What can go wrong`, `Claims to falsify`,
  `Decisions`), empty for none. Consumes: `CASES` (:1143, existing), `CLAIMS` (G5), `ACCEPTED` (G19).
- G8 round file header. Produces: one more header line, `Pre-review: rebase <s> s, tests <s> s, suite <s> s`.
  Consumes: humans; `read-verdict.sh` reads only the last line; `round_line` (`main-watch.sh:902`) reads `Pass:` only.
- G16 round file `Pass:` value `design`. Produces: `Pass: design` and the stdout `DESIGN GO:` line. Consumes:
  `main-watch.sh` `round_line`/`report_wake` (:902, :928, updated), `report_notes` (:1268, updated); `board.sh:158`,
  `:253`, `merge-unit-local.sh:620`, `orca-wait.sh:332` print the kind as written (no change); `--verify` reads the
  reviewer's record head, not the `Pass:` line (updated). G19 consumes `DESIGN` (the host plan: design passes count
  and never stop).
- G17 per-role TTL. Produces: `env.CLAUDE_CODE_PROMPT_CACHE_TTL` in `.claude/main-session.settings.json` (main), in
  each worker worktree's and the Chief-of-Staff worktree's `.claude/settings.local.json`; `subagentPromptCacheTtl`
  in `.claude/settings.json`; config keys `mainCacheTtl`, `workerCacheTtl`, `chiefOfStaff.cacheTtl`; options
  `mainPromptCacheTtl`, `workerPromptCacheTtl`, `relayPromptCacheTtl`. Consumes: Claude Code (each pane), `no-poll-loops.sh`
  (env), `il_cache_ttl_report` (doctor, setup), `il_shadow_report`, `il_options_report` (lists every option, no
  change), `builder-cache-check.sh` (reads `workerPromptCacheTtl`, G17-8), `doctor-options.test.sh` :11-18 (option and
  report lines, updated). Existing consumers of the removed `promptCacheTtl`: `worktree-setup.sh:166`,
  `install-lib.sh:402`, `setup.sh:414`, `paths.sh:1146`, plugin.test.sh :68, plugin-option.test.sh: all changed in G17.
  Revision 4: setup's Needs-you lines (producer `setup.sh:493-495`, each opening with its question's title) are
  consumed by `skills/update/SKILL.md:29` (updated) and printed as they are by `update.sh:69`; the question text
  (producer `skills/setup/SKILL.md`) is consumed by plugin.test.sh :53-75, :198-199, :203 (updated); the config key
  `workerCacheTtl` by worktree-setup.test.sh :31, :36, doctor-run.test.sh :37, plugin-option.test.sh :71 (updated);
  `builder-cache-check.sh` reads the worker answer of `$WT`'s own project; `docs/cost-control.md:14-16` describes it
  (updated). G17's full consumer list, with what changes per hit, is in section 2, G17.
- G5 + G17 `IL_MAIN_LEAN`/`il_main_lean`. G5 drops the ponytail keys; G17 adds the TTL key. Consumes: `setup.sh:484-485`,
  `uninstall.sh:45`, `doctor.sh:67-72`.
- `.claude-plugin/plugin.json` userConfig count (plugin.test.sh :76, 39 today): G5 -1, G20 -1 (five Astra keys out,
  four Fable keys in), G17 +1 (two new, one gone), G10 +3: 41 at the end; the check's text names the change.
- G9 dashboard alerts and G10 units mod consume the snapshot (A3; Decision G10-1's field list). G10 produces no file.
  Revision 3: the snapshot's producer is `dashboard.sh` (unchanged); its shape is `window.DASH = {updatedAt, home,
  projects: {<PP_PROJECT>: {path, workspaces, units: {inFlight, mergedSincePush[{unit, at, sha, how}],
  finishedBuilds, ...}, mainChain, ...}}, ...};`; G10 consumes `projects[PP_PROJECT].units` through its adapter.
  Existing consumers (the dashboard page, `dashboard_alerts.jq`, `cos-watch-alerts.sh`) are unchanged.
- `run-shell-tests.sh` live table (new producer, G10, revision 2). Produces: `<git dir>/commandeck-test-live/<pid>.tsv`
  (`run <epoch> <jobs>`, `file <rel>`, `start <rel> <epoch>`, `end <rel> <ok|FAIL|skip> <secs>`, tab-joined, the
  host's format), removed at exit. Consumes: G10's `readTests` (`parseTestLive`). Existing consumers of the runner's
  output (stdout `-- ` lines, the `$RES` files, `builder-codex-pass.sh`'s and the merge's greps) are unchanged: the
  table is a new file only.
- Seat records `$PP_SCRATCH/seat-<unit>-<role>.txt` (existing producer `seat.sh`, unchanged). New consumer: G10's
  `seatState` (`verdict=`, `phase=`). Existing consumers: `builder-launch.sh` (:149-197), the dashboard.
- Judge roles (G20). Produces: routing role `plan-judge-fable`, options `planJudgeFable{Enabled,Model,Effort,Fast}`.
  Consumes: `plan-tier.sh`, `builder-launch.sh:157`, `seat.sh` (through `pp_route`), `codex-helpers.sh` lanes, the
  doctor's GitHub-read groups, setup's `--profile claude`, `il_routing_merged`. Every existing consumer of the removed
  `plan-judge-astra`/`planJudgeAstra*` is in G20's list (section 2, G20; `rg` of the names, 2026-10-25).
- `merge-unit-local.sh` merge state (existing producer; revision 4: G10 adds one log line). Produces:
  `merge-unit-local.state` (`unit=`, `pid=`, `started=`, `log=`, ...), `merge-unit-local.queue/<unit>@<sha>` (a
  pid), and `$PP_SCRATCH/merge-<unit>.log` (`ATTEMPT unit=<u> pid=<pid> started=<epoch>` first in each attempt, new;
  `STEP <n> <name>:`, `FAILED <step>: <reason>`, `DONE unit=`), truncated per detached lone merge, appended per queued
  attempt (`merge-queue.sh:43-47`). Consumes: existing `pp_merge_active` (`paths.sh:499`), `main-merge-guard`,
  `merge-queue.sh`'s `tail -n 1`/`tail -n 3` (:52, :57, :60), `pp_detach`'s `tail -n 5` to main (`paths.sh:485`), the
  merge tests' line greps (none reads a first line or counts lines); new: G10's `readMerges`, which slices from the
  last `ATTEMPT unit=<u> ` line. G10's gate adds `STEP 4 plugin:` and `FAILED step 4 plugin:` lines in that format,
  which the adapter reads like any other step.
- G16 `report_notes` (`main-watch.sh:1268`). Produces: `NARROWED` (narrowed or design-only wording) and `GO_PASS`
  (`narrowed` | `design-only`). Consumes: :1231, :1248-1251.

## Not ordered (found, not planned)

- Plugin issues 340 to 344, 346 and 347: open on GitHub, not in this unit, by the order.
- Issues 350 to 355 and 361 to 363 are still open on GitHub: 0.47.0 closes them when main pushes.

## Version and CHANGELOG

Main carries 0.47.0 (`.claude-plugin/plugin.json:3`). This unit takes the next free minor at merge time: 0.48.0
unless another unit takes it first. The README badge by hand (`scripts/__tests__/plugin.test.sh:33-34` check it).
One CHANGELOG entry in the 0.47.0 format, naming only this unit's issues: a paragraph per group, "Closes" on every
issue of the Closes line (issue 366 only if G19 is built; issue 367 for the cache), and these behaviour
changes said plainly: the ponytail add-on and its option are gone (remove an installed skill copy by hand); the
first fix round keeps the Builder's model (RD4); the three prompt-cache questions replace the old two (answer them
again; an old `promptCacheTtl` in `.claude/settings.json` can go by hand); the Chief of Staff unfinished-work Stop
hook ships unregistered; the Panel's second plan judge is now a read-only Claude seat on Fable at high
(`plan-judge-fable`, options `planJudgeFable*`), and the Astra judge and its `planJudgeAstra*` options are gone (a
saved answer is read by nothing; an owner routing file's own `plan-judge-astra` entry can go by hand); the units mod
ships, with `run-shell-tests.sh` writing a live table it reads. No release notes, no README rewrite, no backfill (Decisions G11-1, V-1).

## Files edited

- G18: `hooks/hooks.json` ~104; `docs/hooks.md` ~35; `hooks/cos-unfinished-stop.sh` ~1-7; test `scripts/__tests__/plugin.test.sh`
- G5: `scripts/seat.sh` ~412-416; `templates/main-session.md` ~58-64; `templates/_builder-brief-template.md` ~26 and
  the pre-flight lines; `scripts/builder-codex-pass.sh` ~1143, ~1153; `templates/global-rules.md` ~5, ~55-58, ~89-91;
  `templates/ponytail/LICENSE`, `SKILL.md`, `SUMMARY.md` (deleted); `.claude-plugin/plugin.json` ~226-232;
  `scripts/paths.sh` ~1143, ~1162; `config/addons.tsv` ~6; `config/retired.tsv` ~2 and one row;
  `scripts/builder-launch.sh` ~291-294; `scripts/setup.sh` (lines in G5); `scripts/install-lib.sh` ~493-499;
  `scripts/worktree-setup.sh` ~21, ~72-78, ~97-98, ~186-227; `skills/setup/SKILL.md` ~192-197, ~221;
  `skills/uninstall/SKILL.md` ~18; `hooks/dependency-addition-guard.sh` ~3, ~42, ~278; `docs/add-ons.md`,
  `docs/commands.md`, `docs/setup-questions.md`, `docs/worker-panes.md`, `docs/uninstall.md`, `docs/configuration.md`;
  `README.md` ~117, ~141, ~257, ~314; `NOTICE` ~11-15, ~42, ~52-53; tests `scripts/__tests__/plugin-option.test.sh`,
  `scripts/__tests__/rules-audit.test.sh`, `scripts/__tests__/brief-template.test.sh`,
  `scripts/__tests__/builder-codex-pass.test.sh`, `scripts/__tests__/install-lib-setup.test.sh`,
  `scripts/__tests__/install-lib.test.sh`, `scripts/__tests__/profile-revoke.test.sh`,
  `hooks/__tests__/profile-settings.test.sh`, `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/update.test.sh`,
  `hooks/__tests__/dependency-addition-guard.test.sh`, `scripts/__tests__/worktree-setup.test.sh` (where they assert it)
- G8: `scripts/builder-codex-pass.sh` ~1034-1090, ~1361; `hooks/git-safety.sh` ~223-225, the add branch and the
  `--record-add` mode; `hooks/hooks.json` PostToolUse ~66; `docs/hooks.md`; `skills/worktreereview/scripts/collect.py`
  ~486, ~904; `skills/worktreereview/scripts/render.py` ~210-211; tests `scripts/__tests__/builder-codex-pass-rebase.test.sh`,
  `hooks/__tests__/git-safety.test.sh`, `scripts/__tests__/worktreereview.test.sh`
- G9: `scripts/dashboard_alerts.jq` ~56-60 (and `scripts/dashboard.sh` if A3 says absent);
  `hooks/agent-startup-context.sh` ~104-145; `templates/cos-order.md` (new); `scripts/cos-order-check.sh` (new);
  `docs/chief-of-staff.md`; tests `scripts/__tests__/dashboard-alerts.test.sh`, `scripts/__tests__/cos-order-check.test.sh`
  (new), `hooks/__tests__/agent-startup-context.test.sh`
- G12: `scripts/builder-codex-pass.sh` ~103, ~110, ~173; `scripts/seat.sh` ~412-416; `config/routing.json` roles.fixer;
  `.claude-plugin/plugin.json` ~45-58; `templates/global-rules.md` Working and review; `templates/AGENT_STARTUP.md`
  ~70-80; `templates/global-claude.md`; `templates/main-session.md` ~7, ~9-13; `templates/_builder-brief-template.md`
  How to work, ~128-129; `templates/_batch-brief-template.md` ~52; tests `scripts/__tests__/brief-template.test.sh`,
  `scripts/__tests__/builder-codex-pass.test.sh`, `scripts/__tests__/builder-fresh-round.test.sh`,
  `scripts/__tests__/install-lib-setup.test.sh`
- G15: `scripts/builder-codex-pass.sh` ~103; test `scripts/__tests__/builder-codex-pass-suite.test.sh` ~56
- G16: `scripts/builder-codex-pass.sh` ~152-154, ~194, ~312, ~423, ~569-577, ~964, ~1066-1067, ~1121, ~1361-1366,
  ~1448; `scripts/main-watch.sh` ~928-934, ~1250, ~1260-1268; tests `scripts/__tests__/builder-codex-pass-closing.test.sh`,
  `scripts/__tests__/builder-codex-pass-class-return.test.sh` ~35, `scripts/__tests__/main-watch-report-wake.test.sh`
- G17: `.claude-plugin/plugin.json` ~240-253; `scripts/paths.sh` ~1146; `scripts/setup.sh` ~12, ~37-39, ~55, ~119,
  ~213-214, ~394, ~399, ~414-415, ~478, ~493-495, ~629; `scripts/install-lib.sh` ~271-289, ~396-430, ~500-525;
  `scripts/worktree-setup.sh` ~100-102, ~166-170; `hooks/no-poll-loops.sh` ~235 (comment); `config/retired.tsv`
  (one row); `skills/setup/SKILL.md` ~198-205; `docs/setup-questions.md` ~24; `docs/configuration.md` ~57;
  `README.md` ~258-259; `scripts/builder-cache-check.sh` ~2-8, ~18, ~26-28; tests `scripts/__tests__/install-lib-setup.test.sh`,
  `scripts/__tests__/install-lib.test.sh`, `scripts/__tests__/worktree-setup.test.sh`, `scripts/__tests__/doctor.test.sh`,
  `scripts/__tests__/doctor-options.test.sh` ~11-18, `scripts/__tests__/transcript-requests.test.sh` ~138-160,
  `hooks/__tests__/no-poll-loops.test.sh`, `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/plugin-option.test.sh`,
  `scripts/__tests__/rules-audit.test.sh`
- G10: `hooks/units.tsx`, `hooks/units-sources.ts`, `hooks/units.test.tsx`, `hooks/units-sources.test.tsx` (new, from
  host main); `hooks/hooks.json` ~2; `.claude-plugin/plugin.json` (three options); `types/index.d.ts`;
  `scripts/merge-unit-local.sh` a new block after ~512; `docs/dashboard.md`; tests `scripts/__tests__/merge-unit-local.test.sh`,
  `scripts/__tests__/merge-queue.test.sh`, `scripts/__tests__/fixtures/merge-unit-local-setup.sh` (the `claude` stub),
  `scripts/__tests__/plugin.test.sh`; revision 2: `scripts/paths.sh` ~1150, ~1164 (units option cases);
  `scripts/run-shell-tests.sh` ~135-136, ~155-165 (the live table); tests `scripts/__tests__/run-shell-tests.test.sh`
  (last case), `scripts/__tests__/plugin-option.test.sh`
- G16 (revision 2): `scripts/builder-codex-pass.sh` ~1066-1068 (the `SHA` read before the `DESIGN` line)
- G17 (revision 2): `scripts/__tests__/install-lib.test.sh` ~195-231; `scripts/__tests__/doctor.test.sh` ~115-147
- G12 (revision 2): RD6's text in `templates/global-rules.md` Working and review; its greps in
  `scripts/__tests__/brief-template.test.sh`
- G20: `config/routing.json` ~43-63; `.claude-plugin/plugin.json` ~128, ~157-187; `scripts/plan-tier.sh` ~37-38;
  `scripts/builder-launch.sh` ~157; `scripts/codex-helpers.sh` ~51; `scripts/setup.sh` ~268; `skills/setup/SKILL.md`
  ~155-157; `templates/main-session.md` ~65; `docs/configuration.md` ~20; `README.md` ~111, ~244-248; tests
  `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/plan-tier.test.sh`, `scripts/__tests__/seat-launch.test.sh`
  ~108-130, `scripts/__tests__/seat-run-refused.test.sh` ~40, `scripts/__tests__/builder-launch-resume-from-plan.test.sh`
  ~33-81, ~135-137, `scripts/__tests__/install-lib-setup.test.sh` ~43-44, `scripts/__tests__/plugin-option.test.sh`
  ~104-112, ~183-196, `scripts/__tests__/doctor.test.sh` ~213-224
- Revision 3: G10 `hooks/units-sources.ts` `parseSnapshot`, `hooks/units.tsx` `loadPaths`/`readSnapshot`/
  `readMerges`, `scripts/run-shell-tests.sh` ~179-198 (the selection pass), their tests; G17
  `scripts/worktree-setup.sh` ~102 and `scripts/__tests__/worktree-setup.test.sh` after ~39; G20
  `skills/setup/SKILL.md` ~161, `scripts/__tests__/seat-launch-github.test.sh` ~24, ~30, `scripts/__tests__/plugin.test.sh`
  (the setup-key check)
- Revision 4: G10 `scripts/merge-unit-local.sh` ~78 (the `ATTEMPT` line), `hooks/units.tsx` `readMerges` (the
  newest-attempt slice, the pid-matched counts), `hooks/units.test.tsx` (the merge table's fixtures and five new
  cases), `scripts/__tests__/merge-queue.test.sh` (the two-attempt case); G17 `scripts/install-lib.sh` ~503-525
  (`il_main_lean`'s leave branch and answer argument), `scripts/setup.sh` ~485, ~493-495 (the Needs-you titles),
  `skills/update/SKILL.md` ~29, `scripts/builder-cache-check.sh` ~12-13 (the worktree's project), `docs/cost-control.md`
  ~14-16, `README.md` ~118, `scripts/worktree-setup.sh` ~99, ~233 (comments), tests `scripts/__tests__/plugin.test.sh`
  ~53-75, ~198-203, `scripts/__tests__/install-lib-setup.test.sh` (two leave cases), `scripts/__tests__/transcript-requests.test.sh`
  (the per-project case), `scripts/__tests__/worktree-setup.test.sh` ~31, ~36, `scripts/__tests__/plugin-option.test.sh`
  ~71-84, `scripts/__tests__/doctor-run.test.sh` ~37, `hooks/__tests__/dependency-addition-guard.test.sh` ~130,
  ~134, ~151; G20 `scripts/__tests__/doctor.test.sh` ~213 (the Claude group)
- G21 (per the judged host plan and the host commit): `templates/_builder-brief-template.md` ~94-105,
  `scripts/builder-codex-pass.sh` ~1426-1470, `hooks/hooks.json`, the hook scripts and `hooks/lib/run-hook.sh` the
  host plan maps to, their `hooks/__tests__/` files and the ported parity test
- G11: `.github/workflows/release.yml`, `scripts/release-decide.sh`, `scripts/release-notes.sh`,
  `scripts/release-backfill.sh`, `scripts/__tests__/release-notes.test.sh` (new); `scripts/update.sh` ~27
- G19 (per the host commit): `scripts/builder-codex-pass.sh`, `scripts/merge-unit-local.sh`,
  `templates/_builder-brief-template.md`, `README.md` and `docs/` review text; test
  `scripts/__tests__/builder-codex-pass-threshold.test.sh` (new)
- Version: `.claude-plugin/plugin.json` ~3, `README.md` badge, `CHANGELOG.md`

## Done when

1. Every item's named test in sections 1-2 and in "Decisions" is green, and the `Break:` targets read true to a
   reviewer.
2. `bash scripts/run-shell-tests.sh --changed main` is green, plus the callers' tests each group names;
   `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh`
   pass.
3. Builder checks A3, A5, A6, A7 and (when G21 is built) A8 are answered in the evidence file with their outputs;
   G10's field table is there; every round file of this unit was written by main's pass script (A1).
4. G19 is built from the landed host commit, or main has answered that the unit ships without it (then issue 366
   leaves the Closes line). G21 is built from the judged host plan and the landed host commit, or main has said the
   unit ships without item 9 (the 03:00 ET cut-off); the CHANGELOG names G21 only when it is built.
5. Issue 367 (the cache issue) is on the Closes line and in the CHANGELOG.
6. Version 0.48.0 (or the next free minor), the badge and one CHANGELOG entry naming only this unit's issues.
7. A closing (final) pass ends `VERDICT: GO` with no finding named. Every finding P0 to P3 before that went back to a
   fix round.
8. Main, after the merge: marks the mapped drift lines synced. The backfill, release notes and README rewrite wait
   for the owner's order once all plugin work is merged.

## Issue text for item 3

Filed as issue 367 ("Prompt cache per role: Chief of Staff, main and Builders, each 5m, 1h or leave", open,
2026-10-25); its body is the text this section carried in revision 0. Nothing to file.

## Main answers (carried from the judged plan, for the groups here)

1. Worktree ownership: granted only after a successful add on a path proven absent before it; the failed-add test on
   another session's path is in G8.
2. Ponytail removal: `scripts/worktree-setup.sh` (:73, :197) and its summary-hook cleanup, `plugin-option.test.sh`
   and `docs/configuration.md` (:48, :57) are in G5; `config/retired.tsv` is a lint row only; no installed-copy
   cleanup.
3. Units mod: the v2 mod, no stall mechanic and no stall producer (G10), now as host main has it.
4. Release guard: the workflow calls `release-decide.sh`, which the tests run, and a text check pins every later step
   to its output (G11).
5. R13 and R22: RD11 and RD12.
6. Self-gating: this unit's passes run main's pass script (A1).

## Question for the owner

1. Existing ponytail installs (carried; the plan does not wait on it). Installs carrying a saved `ponytail` answer:
   0 on this machine; every other install is unknowable. This unit plans no cleanup: an installed ponytail skill copy
   and a saved answer stay where a setup put them, read by nothing. Choose: (a) leave it so, the CHANGELOG telling
   owners to remove the skill by hand (what this plan builds); or (b) a follow-up unit that removes the installed
   copy through the installation helpers (`scripts/install-lib.sh` `il_own`), only where the install manifest shows
   setup placed it.

The prompt-cache old answers need no question: the count on this machine is 0 (G17).

## Plan change log

- 2026-10-25, revision 0 (from the judged plan `plugin-port-2026-10-25.md`, groups G5, G8-G12; line numbers re-read
  on `9ac91d3`):
  - G5: CORRECTED 5c (Decision G5-3): `REST` carries no plan claims today, so 5c adds a `CLAIMS` block through a
    `plan_section` function rather than reordering an existing one. NEW sites found on re-read: `README.md`, `NOTICE`,
    `skills/setup/SKILL.md:221`, the `global-rules.md:55-58` clause. NEW Decision G5-4 (the host's every-pane off of
    the third-party plugin not ported) and G5-5 (the pre-fill key is `relayPromptCacheTtl`, which G17 keeps).
  - G8: CORRECTED 356 (Decision G8-2): the plugin has no precheck step; the third timed step is the full suite. The
    `plugin.test.sh` hook count the judged plan named does not exist.
  - G10: ports host main's mod (`fdb79064` added). NEW Decision G10-5: the merge gate runs only in a plugin project.
  - G11: the owner's order that nothing publishes, writes notes or backfills in this unit.
  - G12: RD8 dropped (in place); RD4's reader is `builder-fresh-round.sh:128-130`; RD10's test file is
    install-lib-setup.test.sh; RD13 confirmed not built.
  - New groups: G15 (item 4), G16 (item 5), G17 (item 3), G18 (item 7), G19 (item 6, gated, last).
- 2026-10-25, revision 1 (the plan judge's NO-GO, 7 P2 findings and the issue-367 note; each cited line re-read on
  `9ac91d3`; nothing else changed):
  - P2 1, merge gate on every path: G10's gate is its own block after the check (after `merge-unit-local.sh:512`,
    before `state commit` :516) with its own copy of the merged tree, outside the `REUSED`/`CHECK_CMD` branches; red
    fails `step 4 plugin`. Decision G10-5 revised; new tests and `Break:` lines in merge-unit-local.test.sh and
    merge-queue.test.sh; a `claude` stub in `fixtures/merge-unit-local-setup.sh`; three What can go wrong rows; Claim 11.
  - P2 2, merge-state adapter: G10 names what `readMerges` reads (`merge-unit-local.state`, the queue,
    `$PP_SCRATCH/merge-<unit>.log`), `loadPaths`' new `gitDir`, and six ordered rules for running, ended, refused and
    stopped (running before a stale `FAILED`). New Decision G10-6, `hooks/units.test.tsx` cases on plugin-shaped
    fixtures with no `long-jobs` folder, two `Break:` lines, two rows, Claim 6 widened, a Contracts entry. A4 is now
    settled; new Builder check A7 (the plugin root inside a mod).
  - P2 3, cache checker: `builder-cache-check.sh` proves the worker answer (`WANT`; leave exits 0; unanswered is 5m);
    new Decision G17-8, transcript-requests.test.sh cases with `workerPromptCacheTtl=1h` and only
    `ephemeral_1h_input_tokens`, a `Break:` line, one row, Claim 12; the Contracts line no longer says "comment only".
  - P2 4, doctor-options.test.sh: added to G17's sites and the item map; its fixture (:11), option check (:14-15)
    and cache-report check (:17-18) move to the three-role contract; G17-5 gains the per-role leave line.
  - P2 5, class-return test: G16 updates `builder-codex-pass-class-return.test.sh:35`'s grep for the parenthesis,
    placed after "on that design alone" as host `95730a8d` places it.
  - P2 6, watcher wording: G16's `report_notes` keeps the narrowed and design-only wordings apart (`GO_PASS`), the
    narrowed subject and `main-watch-report-wake.test.sh` :47-55 unchanged; a new design-finish case and `Break:` line;
    Decision G16-3 revised; one row; a Contracts entry.
  - P2 7, RD3: restored word for word from the judged plan (`plugin-port-2026-10-25.md:802-813`), including "whose
    test is written" before a fix diff; its test greps that phrase.
  - Issue 367: the cache issue exists; the Closes line, G17's issue bullet, Decision G17-7, Done when 5, the CHANGELOG
    line and section "Issue text for item 3" now name it instead of a pending filing.
  - Size: G10 1,215 -> 1,345, G16 85 -> 100, G17 290 -> 345; total ~3,515 lines, 93 files. Timed checks: the four
    newly edited test files have no time-bound check.
- 2026-10-25, revision 2 (the plan judge's second NO-GO: 6 P2 and 2 P3 findings, each cited line re-read on
  `9ac91d3` and in host main; plus item 8, the owner's order to swap the second plan judge to Fable; nothing else
  changed):
  - P2 1, design SHA order (plan G16): CORRECTED, `SHA` is read right after the pass commit and before the `DESIGN`
    line and `rebase_and_test`; the `SHA=` at :1068 stays and refreshes it. New Decision G16-4, a closing-test case
    run with `SHA` unset and with a stale `SHA`, a `Break:` line, one What can go wrong row.
  - P2 2, activation guard (plan G10): the mod registers in a project whose main has `.claude/commandeck.json`, not
    on the host-local mod file; the test fixture writes that file; the host's outside-project case is renamed. New
    Decision G10-7, a `Break:` line, a `Catches:` line, one row.
  - P2 3, option readers (plan G10): `options.unitsBand`/`unitsPane`/`unitsStatus` in `register`; `pp_option` cases
    and an `auto|on|off` check for the three, so `il_options_report` does not die; `plugin.test.sh:42-46` kept. New
    Decision G10-8, a plugin-option case and a units case per toggle, a `Break:` line, one row.
  - P2 4, test and seat sources (plan G10): a new producer, the runner's live table
    (`<git dir>/commandeck-test-live/<pid>.tsv`, the host's format, removed at exit) in `run-shell-tests.sh`; the mod
    reads only that half of the host's `readTests`, skips a table in a worktree outside `$PP_WORKSPACES` (the merge's
    copy), and counts a merge's files from its log; `seatState` reads the seat records. New Decision G10-9, tests in
    run-shell-tests.test.sh (last, after its timed cases) and units.test.tsx, two `Break:` lines, Accepted failure
    modes 4 and 5, Claims 6 and 13, two Contracts entries, three rows.
  - P2 5, merge attempt (plan G10): a log older than the state's `started=` is read as absent; rules 1 and 3 to 5
    read only a log that counts. Decision G10-6 revised; the case "a dead merge attempt newer than its log's DONE
    reads stopped, with no merge finished toast", a `Break:` line, one row.
  - P2 6, legacy cache tests (plan G17): install-lib.test.sh :195-231 (the `il_cache_ttl` cases and the replay
    harness, which now fails loud on a missing line) and doctor.test.sh :115-147 rewritten for the three roles, none
    kept for the removed behaviour. New Decision G17-9; the item map names install-lib.test.sh.
  - P3 7, RD6: restored word for word (`plugin-port-2026-10-25.md:830-837`), its test greps the dispatch checks.
  - P3 8: `Catches:` lines on A6 and A7.
  - Item 8 (new group G20, built after G12): `plan-judge-astra` replaced by `plan-judge-fable` (Claude, `fable`,
    high, read-only reviewer); the five `planJudgeAstra*` options replaced by four `planJudgeFable*`; plan-tier,
    builder-launch, codex-helpers (lane `planning`, the plugin's), setup, setup questions, main's rules, the
    configuration doc and the README rows follow; eight test files named. The plugin has no platform audit, so no
    Astra judge role stays. Decisions G20-1 and G20-2, Accepted failure mode 6, Claim 14, a Contracts entry, two
    `Break:` lines, one row, a CHANGELOG line, Decision V-1's README list.
  - Size: G10 1,345 -> 1,510, G12 185 -> 187, G16 100 -> 105, G17 345 -> 430, G20 115 (new); total ~3,887 lines, 101
    files; userConfig count 42 -> 41. Timed checks: run-shell-tests.test.sh and seat-run-refused.test.sh named, and
    where doctor.test.sh's edits sit.
- 2026-10-25, revision 3 (the plan judge's third NO-GO: 1 P1, 4 P2 and 1 P3, each cited line re-read on `9ac91d3`
  and in host main; plus item 9, the owner's order to add the Builder-speed unit; nothing else changed):
  - P1, snapshot adapter (plan G10, the "Adapted, not redesigned" bullet): a new "Snapshot adapter" bullet maps the
    plugin's `data.js` field by field to host `parseSnapshot`: this project's `projects[PP_PROJECT].units`, merge
    time `at` for `mergedAt`, `null` lists as empty, no push chain; `loadPaths` prints `PP_PROJECT`. The judge's
    failing input is the fixture of the new units-sources.test.tsx case. Decision G10-1 CORRECTED; a `Break:` line,
    a `Catches:` line, one row, Claim 15, a Contracts line, A7's note on `project.sh`.
  - P2 1, live table selection (plan G10 test progress): CORRECTED, the host's selection pass is ported (skipped
    files listed and ended `skip`, `--own-lane` exclusions never listed); a second run-shell-tests.test.sh case, last
    in the file, with an ordinary and an own-lane fixture under both modes. New Decision G10-10, a `Break:` line,
    one row; Timed checks updated.
  - P2 2, relay 5m (plan G17): the relay branch writes 5m or 1h by path; a worktree-setup.test.sh case from `{}` and
    beside another env key. New Decision G17-10, a `Break:` line, one row.
  - P2 3, fast-tier consumer (plan G20): `skills/setup/SKILL.md:161` sends `planJudgeFableFast`; a plugin.test.sh
    check that every key setup's SKILL.md names is a manifest option. New Decision G20-3, Claim 14 widened, one row.
  - P2 4, GitHub launch test (plan G20): `seat-launch-github.test.sh` :24 and :30 move to the Fable judge (nine test
    files), with a Builder check on its refusal text. Decision G20-3; the item map and Files edited name it.
  - P3, same-second merge attempts (plan G10 merge-state adapter): CORRECTED, the log-mtime test is gone; a recent
    state naming the unit decides its outcome (live running, dead stopped, its step the state's `stage=`), and the
    log's `DONE`/`FAILED` count only with no such state. The revision 2 case is replaced by the judge's same-second
    fixture; a new case for a dead state over an hour old. Decision G10-6 revised; Accepted failure modes 7 and 8;
    Claim 16; the refusal `Break:` line names rule 5; two rows.
  - G20's source: host `abe1f341` (committed on host main), no longer uncommitted; the item map's twin column too.
  - Item 9 (new group G21, LAST, after G19): ports host unit builder-speed-2026-10-25, gated as G19 (built from the
    judged host plan after its GO, host differences ported after the host merge; no host merge by 03:00 ET: main
    says ship without it). Its host plan was not written yet, so the map names the plugin sites and tests the host
    spec allows and leaves the rest "from the judged host plan". New Decisions G21-1 and G21-2, Builder check A8,
    an item-map row, Done when 3 and 4, Files edited, shared-file order.
  - Size: G10 1,510 -> 1,595, G17 430 -> 440, G20 115 -> 127, G21 250 (new, estimate); total ~4,244 lines, 110 files
    (~3,994 and 102 without G21).
- 2026-10-25, revision 4 (the plan judge's fourth NO-GO: 6 P2 and 1 P3, each cited line re-read on `9ac91d3`;
  nothing else changed):
  - P2, merge outcome from an appended log (plan G10 merge-state adapter): REDESIGNED once, not patched. Each attempt
    now opens with `ATTEMPT unit=<u> pid=<pid> started=<epoch>` (`merge-unit-local.sh` after :78, the lock holder
    only, no dry run); with no state for the unit the mod reads only the log's newest attempt (from the last
    `ATTEMPT unit=<u> ` line), and a log with no such line draws nothing. One table lists every case (no state; live
    and dead pid; one attempt DONE, FAILED, unfinished; earlier DONE then later FAILED or unfinished; earlier FAILED
    then DONE; same-second attempts; old log; no ATTEMPT line) with its fixture and test. Running counts come only
    from the attempt whose `pid=` is the state's. New Decision G10-11 (G10-6 revised); five new units.test.tsx cases
    and one merge-queue.test.sh case; three `Break:` lines; Accepted failure mode 7 revised, 9 new; Claim 16 widened;
    the merge-state Contracts entry now names the new line and every log reader; four rows.
  - P2, leave removed main's TTL (plan G17 main's value): CORRECTED, leave writes nothing: `il_main_lean` adds
    setup's recorded TTL to its wanted keys on leave, so the key and its record stay while the file holds setup's
    value. New Decision G17-11 (G17-2 points to it); the rerun test replaced by "a rerun answered leave keeps the 1h
    setup wrote, and its record, and 5m then replaces it" and a new owner-changed case; one `Break:` line; the rerun
    row corrected and one row added.
  - P2, the checker read the caller's project (plan G17 cache checker): `builder-cache-check.sh` reads
    `workerPromptCacheTtl` with `PP_MAIN` from `$WT`'s git common dir (the `worktree-setup.sh:84` idiom). Decision
    G17-8 widened; transcript-requests.test.sh "the check proves the worktree's own project's answer, not the
    caller's" (two git checkouts, the judge's command); one `Break:` line; one row; Claim 12 widened.
  - P2, update skill (plan G17 setup): setup's Needs-you lines open with the three question titles and name their
    flags; `skills/update/SKILL.md:29` matches the three titles and maps each to its flag. New Decision G17-12;
    plugin.test.sh :203 rewritten and a new Needs-you check; one `Break:` line; one row.
  - P2, plugin.test.sh cache assertions (plan G17 text): :68-69 become three option rows, :198-199 three question
    checks plus "no setup text says a 5-minute cache cost main less"; the three questions are written out word for
    word. Decision G17-13.
  - P2, doctor's Claude group (plan G20 doctor.test.sh): :213's Claude group becomes `(orchestrator, plan-author,
    plan-judge-fable, builder, fixer)` by routing key order, with the Codex group `(plan-judge-sol)`.
  - P3, cost-control doc (plan G17 cache checker): `docs/cost-control.md:14-16` is rewritten for the worker answer
    of the Builder's own project; Claim 12's `rg` covers `docs`.
  - Sibling search (the spec's item 3): `rg -n 'cacheTtl|cache-ttl|CacheTtl|Prompt cache|prompt-cache|prompt
    cache|5-minute' scripts hooks skills docs templates config README.md`; new G17 bullet "The other consumers" lists
    each hit with its change or why it stays. New in it: `worktree-setup.test.sh:31`, `:36` (`cacheTtl` fixtures that
    would fail), `plugin-option.test.sh:71-84`, `doctor-run.test.sh:37`, `dependency-addition-guard.test.sh:130`,
    `:134`, `:151`, `README.md:118`, `worktree-setup.sh:99`, `:233` comments. Claim 17 (no removed key, flag or
    question left) and Decision G17-13; one row; the Contracts G17 entry names the consumers.
  - Timed checks: `doctor-run.test.sh` named (fixture edited in place before its timed calls); the other newly edited
    test files have none.
  - Size: G10 1,595 -> 1,690, G17 440 -> 540, G20 127 -> 129; total ~4,441 lines, 113 files (~4,191 and 105
    without G21).
- 2026-10-25, revision 5 (the plan judge's fifth NO-GO: 4 P2 and 1 P3, each cited line re-read on `9ac91d3` and on
  host main; nothing else changed):
  - P2, host gates accept a plan-only commit (plan G19 and G21): CORRECTED, each gate needs the host's unit merge
    commit (scope `(<unit>)`, a `docs(` subject excluded) AND the implementation on host main: `REVIEW_CAP` and
    `passes_on_record` in `.claude/scripts/builder-codex-pass.sh` for G19; `.claude/scripts/post-fix-checks.sh` and
    the `test:post-fix` script, the first thing the host plan's Cut 1 names, for G21. Each gate is written out as a
    command with its PASS and FAIL lines; both run 2026-10-25 and print `FAIL: commit=none` with `1b65d5bd`,
    `cf1846ec` and `8b6ab6c4` present. Decisions G19-1 and G21-1 revised; G21's state note says the host plan is now
    on host main.
  - P2, setup replay against `/config` precedence (plan G17 main's value): precedence kept (`install-lib.sh:459-466`
    unchanged); the replay test, renamed "a /config answer of leave keeps the 1h setup wrote, and its record, a flag
    does not beat /config, and a /config 5m then replaces it", changes the `/config` answer and states the TTL and
    record after each of its five steps, with a step where a flag loses to `/config` and prints the note. The
    owner-changed case sets `/config` to leave too (it had the same fault). Decision G17-11's test line, the `Break:`
    line and two rows follow; one row added.
  - P2, planning-issue parser (plan G10): new bullet "Planning issues" and Decision G10-12; `closesOf` reads `issue
    <n>` and `#<n>` and returns `#<n>`; units-sources.test.tsx "a plan's Closes line names its issues in the
    plugin's form and the host's" with `closesOf('Closes: issue 348, issue 349\n')`; a `Break:` line, a `Catches:`
    line, one row. Found while checking the plan with `ci/leak-test.sh`: the host case with two four-digit hash
    references in its plan fixture would fail the leak check when ported; it is ported with `Closes: issue 12, issue 34`.
  - P2, standalone-test band text (plan G10 test progress): the band asserts the host's `▸ 1 test run` (host
    `sources.ts:322`); the pane and `/units` assert `▸ u  shell 2/2 files · 1 failed (first <the FAIL file>)` (host
    `sources.ts:272`, `kind: 'shell'` from host `units.tsx:164`). The case is renamed "a standalone run-shell-tests
    run shows files done and first failure in the pane and /units, and one test run in the band"; Decision G10-9's
    test line and one row follow.
  - P3, Claim 17: the `.entries[$p].cacheTtl` ownership records in `scripts/install-lib.sh` (`il_cache_ttl`
    :279-288, uninstall's `off` path) are exempt by name; their four `rg` hits are a pass.
  - Timed checks, CORRECTED: `install-lib-setup.test.sh` has time-bound checks (:284, :298, :300, written
    `$(command -v timeout) <n>`, so revision 4's `rg` missed them); G17's two main-TTL cases go after them.
  - Size: G10 1,690 -> 1,700, G17 540 -> 550; total ~4,461 lines, 113 files (~4,211 and 105 without G21).
- 2026-10-26, Builder fix round 1 (the first review pass's findings; nothing else changed):
  - G8: tmp-worktree ownership REDESIGNED: a pending line at PreToolUse, a grant (the session id) in the new
    worktree's own git dir at PostToolUse; only absolute or `~/` paths are owned; the one-word checkout lookup
    follows `-C`. Four rows.
  - G10: the pane opens only while a unit is live; the status line is shared (`hooks/status-line.ts`); merge times
    and spend come from `finishedBuilds` (Decision G10-1). Three rows.
  - G11: decide releases while the tag or the release is missing; the Tag step is idempotent; the Decide step fails
    with its script. Two rows; Claim 7.
  - G9 (360): pass 4, main's five rules with no relay pane, the plan's `Owner's words:` line and the judges' trace
    check. Two rows.
  - G17: the `/config` precedence replay case in install-lib-setup.test.sh (the row's named test now exists).
  - The brief's Data design names the state the batch adds (one row).
- 2026-10-26, Builder fix round 2, design only (the class stale-worktree-owner came back in pass 2: concurrent adds
  let the session whose add failed but exited 0 write the grant first):
  - G8 357 REDESIGNED: one fence, a command that is one plain git call. The grant is written only after such an add
    succeeded (PostToolUse) with the worktree at the path named once by git; a forced remove uses it only when it is
    such a call too. The `pending` line and `$PP_SCRATCH/tmp-worktrees` go. Decision G8-1 rewritten, the stale
    pending row rewritten, three rows added (concurrent adds, chained remove, lost grant retry), Accepted failure
    mode 10 (two gits inside git's own check window), one test for every ordering found so far.
- 2026-10-26, Builder fix round 3 (pass 3 reviewed the design against unchanged code: its findings were the code not
  yet written):
  - G8 357 built as redesigned; G10 planning cost read from `plan.cost` before a Builder; G11 backfill pushes a tag
    origin lacks. Two rows (planning cost, backfill push failed).
  - G21 built from the host commit (main's order: host merged): the post-fix runner, no hook change (the host dropped
    its own); three `Break:` lines, five rows.
  - G19 built from the judged host plan, not a host commit (main's decision plugin-g19-from-plan: the gate still
    fails), plus main's delta: a pass clears an earlier P0/P1 only when every reviewer it declared is on record and
    none names a P0 or P1. Not built, follow-ups: the host's diff exclusions, main-watch's NO-GO wake text, a
    P0-P2-only class repeat, O6 (no plugin record by severity). The other host differences port after the host merges.
  - The host merged (implementation `1fd81a93`): ported its in-table differences: the cap needs an open P2; the
    threshold stop reads what is open over the whole record; the latest pass is the one that ended last; a closing
    pass gets no author's notes and the host's fresh line, narrowed to the history files (the brief stays open).
  - missed-verdict-toast, third return (main: redesign; design pass first): Data design "Verdict toasts", the row
    "verdict first seen", Accepted failure mode 11. The code follows the design pass.
- 2026-10-26, Builder fix round 4 (pass 4: one P1 stale-worktree-owner, one P2 stop-answer-mismatch):
  - G19: the launch gate takes the answer the prescribed route leaves, a row whose question opens with the stop id
    (orca-wait.sh records it under the Orca message id). Row "stop answered by the route".
  - G10: the verdict-toast code, after pass 4 read the design and named no finding on it.
  - G8 357, stale-worktree-owner third return (pass 4; main asked, design-only pass first): the claim beside the path,
    written by an add's PreToolUse while the path is absent and required by the record step; the fence becomes a
    fixed list of add and remove forms (the sweep's `--version` add). Decision G8-1, three rows (delayed record step,
    an add that adds nothing, lost claim), Accepted failure mode 12.

# Plan: plugin-open-2026-10-26b: every open plugin issue, one unit

Owner's words: Order: the owner, 2026-10-26: "start the plugin unit with all open plugin issues". ONE unit, ONE Builder, no split, whatever the file count or line caps say.

Added by the owner by name, 2026-10-26 (plan spec sections 3 and 4): #397, "Helper agents, especially explore, should be
sonnet & haiku respectively."; #398, "The plugin needs a way to prohibit this" (unrequested placeholder UI); #399
(plan spec's #399 section, main's message of 2026-10-26: "the owner added one more issue to this unit"), a read-only
Codex helper for Builders, planners and fixers.
Main's answers to the plan author, 2026-10-26: #397 is in this unit as a native build; #386 is a stated limit (no
plugin twin, `Refs #386` and a one-line issue comment); #385's typecheck is a new `typecheckCommand` project key; #392's
screen code is a setup key whose default and file rule are the host's.

Closes: #384, #385, #387, #390, #392, #393, #394, #395, #396, #397, #398, #399
Refs (stays open): #386

- Planned size: 51 files, 2019 changed lines

Tier: Standard. LOCAL merge only. Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no
test-timeout raise. Tests run on the PC. No red or mutation proofs except the break runs this plan's `Break:` lines
name: each is run red before pass 1 with `red-proof.sh` and recorded in the evidence file as `Mutation-verified: <test
file> -- <check label>: RED, <how>`. One unit, no split.

Source of every port: the host's local main, squash commit `fea64e3e` (`feat(tooling-plugin-waits-2026-10-26)`). Host
issue to plugin issue: 3203 = #384, 3204 = #385, 3205 = #386, 3206 = #387, 3208 = #390, 3211 = #392, 3212 = #394,
3213 = #395, 3214 = #396. Host hunks are cited as `host <file> @@ -<line>` from `git show fea64e3e`. #393, #397,
#398 and #399 have no host fix and are built from their issue text.

Timed checks: `scripts/__tests__/builder-add-work.test.sh` (the `seq 100` wait at :41),
`scripts/__tests__/seat-launch.test.sh` (`COMMANDECK_SEAT_SETTLE_SECONDS=0` launches at :24, :38, :60),
`scripts/__tests__/builder-codex-pass-fresh-round.test.sh` (`timeout 30` at :99), `scripts/__tests__/project-main.test.sh`
(`timeout 20` at :57), `scripts/__tests__/builder-launch-resume-from-plan.test.sh` (the `seq 100` wait at :48). The one
heavy case this unit adds to any of them, a whole NO-GO pass under BSD awk (C8, fresh-round file), goes last in its
file, after :99. Every other new case in these files is light (a refusal before any pane, a probe, one source) and
still goes after the file's last timed check. The other touched test files have no time-bound check (`grep -n
'timeout [0-9]\|timeout --\|^# timeout\|seq [0-9]*); do'`, 2026-10-26); the new merge cases go in a new file,
`merge-unit-local-screens.test.sh`, so `merge-unit-local.test.sh` (`# timeout: 240`) gains nothing. The new
`scripts/__tests__/codex-ask.test.sh` (C10) has two time-bound checks, "a timeout fails loudly" (`--timeout 1` on a
stub that sleeps 30 s and stops on TERM: exit within 3 s) and "a Codex that ignores TERM is killed after the grace"
(`--timeout 1` on a stub that ignores TERM and sleeps 30 s: exit within 5 s), and its one heavy case, "a real Codex
refuses a write" (a signed-in Codex, L7), goes last, after both.

## Main answers

Main's answers to the plan judge's findings, 2026-10-26 (binding):

- Keep the fail-closed deletion check: after closing panes, list them again; an unreadable or nonempty second listing keeps the worktree (C3 item 1, both cases tested).
- Plan-author worktrees allow `Agent` (helpers) the way Builder worktrees do; reviewer and plan-judge seats keep the denial; the generated permissions are tested for a planner and a reviewer (C7 item 3a).
- An approval names the complete added source line, never a bare substring; every prohibited occurrence is checked (C5 item 2).
- The disabled matcher matches only a `disabled` attribute on a control with a literal true value; a variable named `disabled` and a dynamic prop pass (C5 item 1).
- Screen-path matching normalises the edited file against its worktree root, keeping the absolute path for reads (C4 item 1).
- The brief check flags literal always-disabled controls as well as placeholder copy (C5 item 7).

Main's answers to the round-2 plan judge, 2026-10-26 (binding):

- The disabled matcher finds the true end of an opening tag: it skips `{...}` JSX expressions (balanced braces) and quoted attribute values, so `=>` and `>` inside them do not end the tag (C5 item 1).
- `codex-ask.sh`'s timeout is a deadline then a forced kill: TERM at the deadline, KILL after a 2 s grace, and a timeout error distinct from every other failure (C10 item 1).
- The equality-versus-substring red proof runs on the bare-substring approval case, which goes red under substring matching (C5 Break lines).
- A call whose answering model cannot be read fails loudly, exit 1 with a message naming the missing `model:` header, and never records `unknown` as success (C10 item 1).

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

- L1 (#386). The plugin ships no Stop typecheck hook and no tier-1 Stop hook, so neither host hunk of 3205 (cache
  seeding in the host's typecheck hook, the "no result from" line in the host's tier-1 hook) has a place to land.
  `jq -r '.hooks.Stop[].hooks[].command' hooks/hooks.json` lists four Stop hooks: context-clear-stop, ask-stop-records-
  decision, cos-inbox-waiter-stop, opus-orchestrator-autonomy; `rg -n -i -l 'typecheck|tsbuildinfo|tier.?1' hooks
  scripts config` lists only comments and patterns in git-ignore-warn, builder-event-log, unit-cost, codex-dispatch and
  suite-rerun-guard (2026-10-26). Nothing is ported; the merge says `Refs #386` and main leaves a one-line comment.
- L2 (#393). The PC has no BSD awk: `awk` there is GNU Awk 5.2.1 (`/usr/bin/awk -> /usr/bin/gawk`), with mawk and dash
  installed and no zsh (`ssh <peer> 'readlink -f $(command -v awk); command -v zsh dash mawk'`, 2026-10-26); gawk and
  mawk both accept the construct that BSD awk refuses. So the BSD-awk NO-GO case runs only on a host whose
  `/usr/bin/awk --version` prints `awk version` (the Mac: `awk version 20200816`); on the PC the static check of the
  construct is what runs. The Builder runs the fresh-round file once on the Mac and pastes its summary line in the
  evidence file.
- L3 (#396). The plugin's bound run (`$PP_SCRATCH/current-run`) held 7,392 completed, 162 failed, 21 ready and 2
  dispatched tasks (`orca-ide orchestration task-list --run <run> --json`, counted with python, 2026-10-26 17:15 local).
  Of the 23 open ones, 2 are Builder tasks of merged units whose worktrees are gone (plugin-open-issues-2026-10-26,
  release-notes-style-2026-10-26; both have a `mergeSha` row in the unit ledger), 1 is named by another seat record,
  and 20 are in no seat record. The sweep closes the 2 and lists the 20 as `no record`; it never closes those.
- L4 (#398). The edit-time block sits in `hooks/edit-content-tripwires.sh`, a strict-tier hook (`hooks/__tests__/hook-
  tier.test.sh:14` lists it; the hook exits at :25 unless `strictHooks` is on), so it fires only where the project
  turned strict hooks on. In every tier the merge check and the review's P1 catch the same placeholder UI.
- L5 (#387). Unexplained idle starts at the existing 120 s `WAIT_ON_OWNER` (`skills/worktreereview/scripts/collect.py:49`).
- L6 (#397). Where Claude Code loads the plugin's `hooks/hooks.json` as well as a worker worktree's settings, the
  model guard runs twice on one Agent call. The second run sees the configured model already named and prints nothing
  (Decision 19), so the cost is one hook process (the guard's `ms_body` was 23-37 ms in the fire log rows of
  2026-10-22).
- L7 (#399). The Codex helper's sandbox is Codex's own; the plugin pins `-s read-only` and a working folder outside
  the repository, and only a signed-in Codex can show the refusal. Measured on the Mac, 2026-10-26, Codex CLI
  0.164.0, `codex exec --ephemeral -s read-only -C <fixture repo> -m gpt-6.1-sol` asked to run `echo changed > a.txt`:
  rc 0, answer "Write failed: operation not permitted for a.txt", `a.txt` unchanged. So "a real Codex refuses a write"
  runs only where `codex login status` succeeds, else prints `note: no signed-in Codex here` and counts nothing; the
  Builder runs it once on the Mac and pastes its summary line in the evidence file. Every other case uses a stub.

## 1. Item map (what exists, what the host built, where it lands, the test)

| Issue | Host hunks ported (`fea64e3e`) | Plugin today (file:line) | Lands at | Cut |
|---|---|---|---|---|
| #394 | host `builder-launch.sh` @@ -46 (one loop over every argument, `needval`, unknown option and extra argument refused) | the loop ends at the first word that is not an option (`scripts/builder-launch.sh:52-65`, `*) break`); a value option takes the next word whatever it is (`:59-62`); `--help` is read only as the first word (`:47`) | `scripts/builder-launch.sh:47-69` | C1 |
| #384 | host `plan-check.sh` (new), host `builder-launch.sh` @@ -160 and @@ -207 (checks moved out), host `seat.sh` @@ -221 (judge launch runs it), host `plan-author-spec.md` @@ -117 and `rules/planning.md` @@ -78 (prompt lines) | the plan checks live inline in the launcher: Prior art `:80`, Data design `:83-88`, `plan_checks` `:110-132` (What can go wrong, size line, `Test:` lines); a judge launch checks nothing (`scripts/seat.sh:395`) | new `scripts/plan-check.sh`; `scripts/builder-launch.sh:79-88`, `:110-132`, `:198`, `:214`; `scripts/seat.sh` after `:308`; prompts `:424`, `:429` | C1 |
| #392 launch | host `plan-check.sh` mockup loop, host `plan-author-spec.md` `Mockup:` line | no `Mockup:` line is read anywhere | `scripts/plan-check.sh` | C1 |
| #385 work | host `builder-add-work.sh` @@ -11 (`--unless` probes, exit 4 already done, the hand-off lists absent probes), host `main-session.md` @@ -143 | sends whatever the rulings file holds (`scripts/builder-add-work.sh:16-26`) | `scripts/builder-add-work.sh:9-38`; `templates/main-session.md:99-102` | C2 |
| #385 typecheck | host `builder-codex-pass.sh` @@ -1049 and @@ -1168 (`typecheck_green` after `rebase_and_test`) | a closing pass starts after `rebase_and_test` (`scripts/builder-codex-pass.sh:1372`) with no typecheck; the plugin has no typecheck command | `scripts/builder-codex-pass.sh` after `:1369`, call after `:1372`; `scripts/setup.sh`; `skills/setup/SKILL.md:172-180` | C2 |
| #396 | host `unit-close.sh` (new), host `merge-unit-local.sh` @@ -876 (step 5 calls it before the panes close), host `main-session.md` @@ -143; host `ship-unit.sh` has no twin (the plugin has no ship script) | no step closes a Builder's dispatch task; the record's `task=` line is written at `scripts/seat.sh:450`; `pp_task_close` `scripts/paths.sh:627` | new `scripts/unit-close.sh`; `scripts/merge-unit-local.sh:128` (start of `cleanup_step`); `templates/main-session.md:93-96` | C3 |
| #392 merge | host `merge-unit-local.sh` @@ -102 (`check_screens`) and @@ -308 (its call), host `_builder-brief-template.md` @@ -22 | step 1 reads no screen evidence (`scripts/merge-unit-local.sh:211-241`) | new `hooks/lib/screen-code.sh`; `scripts/merge-unit-local.sh` after `:241`; `templates/_builder-brief-template.md` after `:32`; setup key `screenPaths` | C4 |
| #398 | none: native build | the content tripwire blocks only placeholder comments (`hooks/edit-content-tripwires.sh:259-277`); no merge or review check of placeholder UI | `hooks/lib/screen-code.sh`; `scripts/merge-unit-local.sh` after `:241`; `hooks/edit-content-tripwires.sh` beside `:275`; `scripts/builder-codex-pass.sh:138-141`, `:924`, `:1404`; `templates/_builder-brief-template.md`; `scripts/plan-check.sh`; `scripts/seat.sh:429` | C5 |
| #387 | host `unit-hold.sh` (new), host `collect.py` @@ -51, @@ -309, @@ -693, @@ -787, @@ -831, @@ -850, @@ -914, @@ -941, @@ -955, host `render.py` @@ -22, @@ -336, @@ -523, host `orchestration-reference.md` line | holds are not recorded; time with no session open stays `none` and counts in its stage (`collect.py:746-811`, `:829`) | new `scripts/unit-hold.sh`; `skills/worktreereview/scripts/collect.py:52`, `:254`, `:674`, `:765`, `:811`, `:813`, `:829`, `:893`, `:916-917`, `:937`; `render.py:25`, `:343-347`, `:543`; `templates/main-session.md`; `skills/worktreereview/SKILL.md` | C6 |
| #397 | none: native build (the host's own guard hardcodes the models) | `hooks/agent-model-guard.sh:19-31` hardcodes Explore haiku, general-purpose and debugger sonnet; it is registered only in `hooks/hooks.json:37-38`; `worktree-setup.sh --builder` registers its own two hooks only (`scripts/worktree-setup.sh:226-250`); the guard's own failure and the runner's no-Bash-4 line (`hooks/lib/run-hook.sh:19`) reach no one | `config/routing.json:56-63`; `scripts/paths.sh:724-725`; `hooks/agent-model-guard.sh`; `scripts/worktree-setup.sh` (every run); `hooks/lib/run-hook.sh:19` | C7 |
| #393 | none: native build | `printf ... n[c] == 1 ? "" : "s" ...` at `scripts/builder-codex-pass.sh:1806`, which BSD awk refuses (A1) | `scripts/builder-codex-pass.sh:1806` | C8 |
| #395 | host `paths.sh` @@ -12 (the `BASH_VERSION` refusal) | `scripts/paths.sh:48`, `:55`, `:75` use `${BASH_SOURCE[0]}` (A7 reproduces the failure) | `scripts/paths.sh` after `:18` | C8 |
| #390 | host `units.tsx` @@ -87 (the sibling note) has no twin: the plugin's units hook reads one snapshot, this project's entry (`hooks/units.tsx:65-75`, `hooks/units-sources.ts:117`), and shows its age (`units-sources.ts:271`) | no sibling reader (A5) | pin test in `hooks/units-sources.test.tsx` | C8 |
| #399 | none: native build | no pane can ask Codex anything; the pass's sign-in probe already runs `codex exec --ephemeral --skip-git-repo-check -s read-only` from outside the repository through `codex-no-helpers` (`scripts/builder-codex-pass.sh:1299-1306`); helpers in the review are Claude subagents only (`collect.py:692-693`) | new `scripts/codex-ask.sh`; `PP_HELPER_LINE` (C7 item 2a); `scripts/worktree-setup.sh` allow list; `collect.py`, `render.py` | C10 |
| #386 | host `typecheck.sh` @@ -51/-108/-119 and `tier1-stop.sh` @@ -213: no twin (L1) | none | none | C9 |

## 2. Cuts (build order)

Each cut: what it changes, Produces / Consumes, existing consumers of a contract it changes, size (changed lines, code
+ tests + docs), acceptance tests. "flip" is an existing check whose expected value changes.

Shared-file edit order: `scripts/plan-check.sh` C1, C5; `scripts/seat.sh` C1, C5, C7; `scripts/builder-codex-pass.sh`
C2, C5, C7, C8; `scripts/merge-unit-local.sh` C3, C4, C5; `hooks/lib/screen-code.sh` C4, C5; `scripts/setup.sh` and
`skills/setup/SKILL.md` C2, C4; `templates/_builder-brief-template.md` C4, C5, C7; `templates/main-session.md` C2, C3,
C6; `skills/worktreereview/scripts/collect.py`, `render.py` and `worktreereview.test.sh` C6, C7, C10;
`builder-codex-pass-fresh-round.test.sh` C7, C8; `scripts/paths.sh` C7, C8, C10; `scripts/worktree-setup.sh`,
`worktree-setup.test.sh`, `hooks/lib/helper-pane.sh` and `seat-plan-marker.test.sh` C7, C10; `docs/*`, `README.md` with each cut; `CHANGELOG.md` C9 last.

### C1 -- #394, #384, #392 launch: arguments anywhere, one home for the plan checks, run before every judge (~260 lines)

1. **Arguments (#394, host @@ -46).** `scripts/builder-launch.sh:47-69` becomes one loop over every argument before
   `paths.sh` is sourced: `-h|--help` anywhere prints the header help (today's `sed` line) and exits 0; flags
   `--risky --dry-run --small --skip-plan --from-plan`; value options `--keep --model --effort --reason`, each through
   `needval` (`<option> needs a value` and the usage line, exit 2, when the next word is missing or starts with `--`);
   any other `-*` word is `unknown option <word>` and the usage line, exit 2; other words are positionals. A third
   positional is `extra argument <word>` and the usage line, exit 2. `UNIT=${POS[0]:?$USAGE}`, `BATCH=${POS[1]-}`;
   the rest of the launcher is unchanged (the `--reason`-picks-the-model rule at `:67` stays where it is).
2. **`scripts/plan-check.sh` (new, #384, host `plan-check.sh` adapted).** `plan-check.sh [--batch-only] <plan file | - |
   ''> <batch or ''> [<label>]`. `-` reads the plan text on stdin; `''` is a plan-less (Skip) batch; the label names
   the plan in every message (default: the plan path). It holds the plugin's own checks, moved byte for byte with
   their messages and their order: with a batch, Prior art (`builder-launch.sh:80`) and Data design (`:83-88`, its
   `has_section` with it); with a plan or a Skip batch, What can go wrong (batch or plan), and with a plan the size
   line and the untested items (`:113-126`); then the #392 mockup check (item 3). `--batch-only` runs the batch checks
   alone. Pass: prints `size <files> <lines>` when a plan was read, exit 0. Fault: the first `REFUSED:` line on
   stderr, exit 2. An unreadable plan or batch is `REFUSED: cannot read <file>`, exit 2. Writes nothing.
3. **Mockups (#392 launch, host plan-check mockup loop).** A plan names each mockup on a line `Mockup: <path or URL>`
   outside a fenced block (the size line's fence rule). With a batch, a mockup the batch text does not carry is
   `REFUSED: <plan> names the mockup <m> (a Mockup: line) and <batch> does not carry it: the batch is the Builder's
   brief, so name the mockup there`; a path (not `http(s)://`) that is not a non-empty file, relative to the plan's
   checkout (or `PLAN_CHECK_ROOT` for stdin), is `REFUSED: <plan> names the mockup <m>, which does not exist (<file>)`.
   With no batch (a judge with none found) only the file check runs.
4. **The launcher calls it.** `:79-88` become `bash "$HERE/plan-check.sh" --batch-only '' "$BATCH" || exit 2`, at the
   same place, so a batch refusal still comes before the Launch-line and plan checks. `plan_checks` (`:110-132`) keeps
   its name and the small-NO-GO branch; its checks become one call, `PCOUT=$(PLAN_CHECK_ROOT=<root> bash
   "$HERE/plan-check.sh" "${1:+-}" "$BATCH" "${PLAN:-}" <<<"${1:-}") || exit 2`, and `PLINES` is read from `PCOUT`.
   The root is `$WT` for `--from-plan` (the frozen plan is that worktree's) and `$PP_MAIN` otherwise.
5. **Judge launches (#384, host seat.sh @@ -221).** In `scripts/seat.sh launch`, after the read-only spec check
   (`:296-308`) and before the Claude MCP check, the worktree, the pane, the task or the record: for a `plan-judge-*`
   role whose spec has the whole line `Plan: .claude/plans/<unit>.md` and whose `$WT/.claude/plans/<unit>.md` exists
   (the condition of `:395`, so exactly the judges that certify the plan), `bash "$PP_SCRIPTS/plan-check.sh"
   "$WT/.claude/plans/$UNIT.md" "$B" >/dev/null || exit 2`, where `$B` is the first of
   `$WT/.claude/briefs/$UNIT-batch.md` and `$PP_MAIN/.claude/briefs/$UNIT-batch.md` that exists, else `''`. Every
   launch of such a judge runs it, a re-judge included. Catches: a judge round spent on a fault the launcher refuses
   in seconds (the issue's lost round); no step checks a plan before its judge today.
6. **Prompts.** The plan-author prompt (`seat.sh:424`) gains: "Before PLAN-DONE run `plan-check.sh
   .claude/plans/<unit>.md <batch>` and fix every REFUSED: line; name each mockup on its own `Mockup: <path or URL>`
   line and make sure the batch carries it." The plan-judge prompt (`:429`) gains: "plan-check.sh has passed this plan
   (seat.sh runs it before every judge launch), so report none of its checks: the sections, the size line, the
   `Test:` lines, the `Mockup:` lines." Catches (author line): a refused judge launch and a second author round for a
   fault found in seconds.

Produces: `plan-check.sh` CLI and its `size <files> <lines>` line; the launcher's new refusals (`<option> needs a
value`, `unknown option`, `extra argument`); the judge-launch refusal; two prompt sentences.
Consumes: the launcher's `PLAN`, `BATCH`, `PLANS`, `FROZEN`; `paths.sh` `PP_MAIN`; `seat.sh` `WT`, `SPEC`, `PP_SCRIPTS`.
Existing consumers of a changed contract: the launcher's argument list (docs `first-build.md:16`, `:104`,
`review-loop.md:101`, `worker-panes.md:21`, `plan-tier.sh:52`'s printed suggestion: all put options first, which
still parses); its refusal texts (`builder-launch-resume-launch-line.test.sh:33-53`,
`builder-launch-resume-from-plan.test.sh:101-116`: unchanged bytes); the judge launch (`seat-run.test.sh:10`, `:21`,
`:51` give a `Plan:` judge the one-line plan `the plan`, which plan-check refuses: the fixture plan becomes one that
passes, A12); the plan-author prompt checks (`seat-plan-marker.test.sh:30-38`: their patterns still match).
Size: plan-check.sh 110, builder-launch.sh 70, seat.sh 12, tests 70.

Acceptance tests:
- `scripts/__tests__/builder-launch-resume-launch-line.test.sh` (dry-run launches): new "dry-run in every position
  launches nothing" (before, between and after the positionals: no seat call, rendered brief printed); new "keep after
  the batch takes effect"; new "an extra argument is refused"; new "an unknown option is refused naming it"; new "a
  trailing option with no value is refused"; new "a value option given a flag is refused and launches nothing"
  (`--skip-plan u b.md --reason --dry-run` with an otherwise valid Skip batch: exit 2, no seat call, no worktree); new
  "a plan mockup missing from the batch is refused"; new "a mockup file that does not exist is refused"; new "a plan
  mockup in the batch launches"; new "a fenced Mockup line is not a mockup"; kept: every existing case of this file and
  of `builder-launch-resume-from-plan.test.sh`.
- `scripts/__tests__/seat-launch.test.sh` (after :60): new "a judge launch on a Tests: plan is refused" (rc 2, no
  `terminal create`, no task, no record, the message names the item); new "a judge launch on a plan with no size line
  is refused"; new "a judge with no Plan: line is not checked"; kept: every existing case.
- `scripts/__tests__/seat-run.test.sh`: kept, on the passing fixture plan.

Break: scripts/__tests__/seat-launch.test.sh -- a judge launch on a Tests: plan is refused -- scripts/seat.sh the plan-check.sh call in launch
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- a plan mockup missing from the batch is refused -- scripts/plan-check.sh the mockup-in-batch refusal
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- dry-run in every position launches nothing -- scripts/builder-launch.sh the positional arm of the argument loop (replaced by break)
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- an extra argument is refused -- scripts/builder-launch.sh the third-positional refusal
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- a value option given a flag is refused and launches nothing -- scripts/builder-launch.sh needval

### C2 -- #385: probes before added work, a green typecheck before a closing pass (~140 lines)

1. **Probes (host @@ -11).** `scripts/builder-add-work.sh <unit> --unless '<path>:<text>' [--unless ...] [--small
   --reason '<one line>']`, options in any order after the unit. Each probe is `git -C "$WT" grep -qF -e <text> HEAD
   -- <path>` (the branch's committed HEAD). After the first-pass refusal (`:23`) and the rulings-file check (`:24`),
   before the pane lookup: no `--unless` is refused, exit 2 ("added work needs --unless '<path>:<text>' for each item,
   so work already on the branch is never sent; nothing was sent"); every probe found is exit 4, "already done on
   <branch> at <sha12>: <probes>; nothing was sent"; a `git grep` that fails (rc above 1) is exit 1, "cannot read the
   branch in <wt>". Otherwise sent as today, and the hand-off gains one line under the acknowledgement: "Not yet on
   your branch, by main's probes (<path>:<text>): <absent probes>". The header's exit list gains 4. Catches: added work
   the branch already has, which reopened a converged loop (the issue); nothing reads the branch before a send today.
2. **`typecheckCommand` (main's answer).** A new optional project key in `.claude/commandeck.json`, written by setup
   alone: `--typecheck-command '<cmd>'` (in `TAKES`, `scripts/setup.sh:57`; read back with `old` at `:119`; parsed
   beside `--test-command` at `:313`; written beside `testCommand` at `:530`). `skills/setup/SKILL.md` question 9 gains
   a follow-up: Ask "Typecheck before the closing pass": <detected> (recommended) | None | Type my own; detected is
   `npm run typecheck` when package.json has that script, else `npx tsc --noEmit` when a `tsconfig.json` is at the
   root, else None is recommended. `docs/setup-questions.md`, `README.md:112` and `docs/configuration.md:63` name it.
3. **The closing-pass gate (host @@ -1049).** New `typecheck_green` in `scripts/builder-codex-pass.sh`, after
   `rebase_and_test`'s definition, called right after `rebase_and_test` (`:1372`), `final` passes only: reads
   `typecheckCommand` from `$MAIN_OF_WT/.claude/commandeck.json`; none: prints "no typecheckCommand set: no typecheck
   before the closing pass" and returns; else runs it in `$WT` (`bash -c`), output to
   `$PP_SCRATCH/$UNIT-typecheck-r$N.log`; red: `die` "a closing pass needs a green typecheck, and `<cmd>` is red in
   <wt> (log <path>); no reviewer was run. Fix it, then run the pass again: builder-codex-pass.sh <unit> <N> final"
   plus the log's first 10 lines; green: "typecheck before the closing pass: green (<cmd>)". The rebase-pending file is
   untouched by it, so a rerun retests. Catches: a closing pass spent on a tree whose types are red (the issue); the
   merge check runs only `testCommand`, which need not typecheck, and only after the pass.

Produces: exit 4 and the probe refusal of `builder-add-work.sh`; the `typecheckCommand` key; the gate's die and its two
lines. Consumes: `git grep`; `MAIN_OF_WT`, `KIND`, `die`, `PP_SCRATCH`.
Existing consumers of a changed contract: callers of `builder-add-work.sh` (`templates/main-session.md:99-102`,
`templates/_batch-brief-template.md:40`: both gain the `--unless` form; no script calls it);
`builder-add-work.test.sh`'s `add` and `addx` helpers (every send now passes a probe: `--unless 'new.txt:NOT-YET'`);
`setup.sh`'s commandeck.json writer (the new key rides with the answers; a re-run keeps it through `old`); the setup
tests that pin the flag list (A8).
Size: add-work 35, its test 35, the gate 22, its test 30, setup.sh 8, SKILL.md 6, docs 5.

Acceptance tests:
- `scripts/__tests__/builder-add-work.test.sh` (the worktree `$W` becomes a git repository with one commit holding
  `done.txt` = `PROBE-DONE`; new cases after :41): "no probe is refused" (exit 2, nothing sent, no hand-off); "work
  already on the branch is answered already done" (exit 4, the line names the branch, a 12-character sha and the
  probe, nothing sent); "one of two probes present still sends" (the hand-off names only the absent probe); "a probe
  that git cannot read is refused"; kept: every existing case, each now with a probe.
- `scripts/__tests__/builder-codex-pass-rebase.test.sh`: "a closing pass on a red typecheck is refused before any
  reviewer" (typecheckCommand prints `error TS2322` and exits 1: pass exit 2, the line names the command and the
  error, no round file); "a closing pass with no typecheckCommand runs no typecheck and says so"; "a green typecheck
  lets the closing pass run".

Break: scripts/__tests__/builder-add-work.test.sh -- work already on the branch is answered already done -- scripts/builder-add-work.sh the all-present exit 4
Break: scripts/__tests__/builder-add-work.test.sh -- no probe is refused -- scripts/builder-add-work.sh the no-probe refusal
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a closing pass on a red typecheck is refused before any reviewer -- scripts/builder-codex-pass.sh the typecheck_green call

### C3 -- #396: a finished unit's Builder task is closed, from its own seat record (~295 lines)

1. **`scripts/unit-close.sh` (new, host `unit-close.sh` adapted).** `unit-close.sh <unit> merged | <unit> drop
   '<reason>' | --sweep [--apply]`. Sources `paths.sh`. The task ids are every `task=` and `answer_task=` line of
   `$PP_SCRATCH/seat-<unit>-builder.txt` (written at `seat.sh:450`; answer tasks as `pp_seat_open_ask` reads them,
   `paths.sh:606-617`) not yet marked `settled=<task>` there; never the task list's spec text. Every close goes
   through `pp_task_close` (`paths.sh:627`), which refuses while the Builder's pane works or has an open question; on
   success the record gains `settled=<task>` (seat.sh's own marker, `:681-689`), starting a fresh line when the last
   byte is not a newline.
   - `merged`: closes each task `completed`; prints `STEP 5 task: closed <task> completed` or `STEP 5 task NOT closed:
     <why>; unit-close.sh --sweep --apply closes it later`; no record: the NOT-closed line, exit 1.
   - `drop '<reason>'`: refuses when the unit ledger (`$PP_MAIN/.claude/metrics/unit-ledger.jsonl`) has a `mergeSha`
     for the unit that is an ancestor of local main ("REFUSED: <unit> is merged (<sha12> on main); drop is for an
     unmerged unit"); closes each task `failed` with `{"reason": ...}`, a refused close stopping before anything is
     removed; then closes the worktree's panes (`pp_worktree_panes` and `pp_pane_close`, as `cleanup_step` does,
     `merge-unit-local.sh:133-137`), stops its Codex helpers (`codex-helpers.sh stop`), then lists the worktree's panes
     again through the same reader (`cleanup_step`'s second listing, `merge-unit-local.sh:140-143`: a close that
     answered ok is not a pane gone), and only when that listing reads and is empty runs `orca-ide worktree remove
     --worktree "path:<wt>" --force`. A first listing that cannot be read, a pane that does not close, a second listing
     that cannot be read, or a second listing that still names a pane keeps the worktree: `KEPT <wt>: <why>` (the
     handles still listed, or "the pane list could not be read after the close"), exit 1, the tasks already failed (a
     rerun removes it).
   - `--sweep`: reads the task list of the bound run (`${COMMANDECK_RUN:-<$PP_RUN_FILE>}`; unreadable: exit 1 naming
     it); for every Builder record whose worktree is gone, skipping `<repo>@<unit>` records (another repository's,
     `seat.sh:76`) and live worktrees, each open task (`pending|ready|dispatched|blocked`) would close `completed`
     when the unit is merged by the same ledger test, else `failed`; dry run prints `would close <task> <status>
     <unit>`; `--apply` closes. Every open task named in no seat record is listed `no record <task> <status>` and never
     closed. Last line: the counts.
2. **The merge calls it (host @@ -876).** First line of `cleanup_step` (`scripts/merge-unit-local.sh:128`), before
   any pane closes: `bash "$HERE/unit-close.sh" "$UNIT" merged || true`. So the normal merge (`:687`) and `--cleanup`
   (`:192`, a hand merge's step 5) both close it, and `pp_task_close` still sees the Builder's pane. A refusal is its
   printed line and never this exit code (the merge has landed). Catches: the open Builder tasks the issue counted; no
   step closes a Builder task today.
3. **Docs.** `templates/main-session.md:93-96` (the hand-merge bullet) gains: "An unmerged unit is removed only by
   `unit-close.sh <unit> drop '<reason>'`; `unit-close.sh --sweep` lists Builder tasks left open by units already
   gone, `--sweep --apply` closes them." (Lines joined so the file stays at its 200-line cap, A10.)
4. **The one-off sweep.** After the merge, main runs `unit-close.sh --sweep`, checks the list (2 expected, L3), then
   `--sweep --apply`. The Builder runs the dry run once against a stub (never the live run) and pastes its count; it
   never applies.

Produces: `unit-close.sh` CLI and its lines; `settled=` lines from a second writer. Consumes: `pp_task_close`,
`pp_worktree_panes`, `pp_pane_close`, `PP_RUN_FILE`, the unit ledger's `mergeSha`, the seat record's `task=`,
`answer_task=`, `settled=`.
Existing consumers of a changed contract: `settled=` is read by `seat.sh`'s settle loop (`:685-689`), which skips a
settled task (a task closed by unit-close is never closed twice); the merge's step 5 output lines
(`merge-unit-local*.test.sh` read `STEP 5 cleanup` lines only: the new `STEP 5 task` line matches none of their
patterns, A13).
Size: unit-close.sh 120, merge 3, unit-close test 150, merge case 20, docs 3.

Acceptance tests:
- `scripts/__tests__/unit-close.test.sh` (new; a stub `orca-ide` first on PATH: a fixture task list, every
  `task-update` logged, `worktree ps` saying idle unless the case says working; fixture seat records and ledger):
  "a merge closes the record's task and its answer tasks completed"; "another unit's task is untouched"; "no record
  closes nothing"; "a working Builder refuses and the record gains no settled line"; "a dropped unit's task is
  failed and its worktree removed"; "a merged unit cannot be dropped"; "a working Builder refuses the drop and nothing
  is removed"; "a drop keeps the worktree when a closed pane is still listed" (the stub's `terminal close` answers
  `{"ok":true}` and its second `terminal list` still names the pane: no `worktree remove` in the log, `KEPT` naming the
  handle, exit 1); "a drop keeps the worktree when the second pane listing cannot be read" (the second `terminal
  list` exits 1: no `worktree remove`, exit 1); "the sweep closes a merged gone unit completed and an unmerged gone one failed, and skips a live one";
  "the sweep skips another repository's record and lists a task with no record"; "the sweep dry run changes nothing";
  "a settled task is not closed again".
- `scripts/__tests__/merge-unit-local-screens.test.sh` (new, C4's file): "a merge closes its Builder task completed"
  (a stub `unit-close.sh` in the copied scripts logs its arguments: `<unit> merged`, before the first `terminal
  close`); "a refused task close leaves the merge's exit code and cleanup".

Break: scripts/__tests__/unit-close.test.sh -- a merged unit cannot be dropped -- scripts/unit-close.sh the merged refusal in drop
Break: scripts/__tests__/unit-close.test.sh -- a drop keeps the worktree when a closed pane is still listed -- scripts/unit-close.sh the nonempty second listing check before the remove
Break: scripts/__tests__/unit-close.test.sh -- a drop keeps the worktree when the second pane listing cannot be read -- scripts/unit-close.sh the unreadable second listing check before the remove
Break: scripts/__tests__/unit-close.test.sh -- the sweep closes a merged gone unit completed and an unmerged gone one failed, and skips a live one -- scripts/unit-close.sh the worktree-exists skip in the sweep
Break: scripts/__tests__/unit-close.test.sh -- another unit's task is untouched -- scripts/unit-close.sh the record path (replaced by a seat-*-builder.txt glob)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a merge closes its Builder task completed -- scripts/merge-unit-local.sh the unit-close.sh call in cleanup_step

### C4 -- #392 merge: screen code is a setup setting, and a screen change merges only with evidence (~200 lines)

1. **`hooks/lib/screen-code.sh` (new, sourced by the merge script and the content tripwire).** `screen_prefixes
   <project dir>`: the `screenPaths` array of `<dir>/.claude/commandeck.json`, one folder prefix a line; with no
   `screenPaths` key, the host's folder `web/src/` (the default, main's ruling); an empty array: none.
   `is_screen <path>`: the path starts with one of the prefixes, ends `.tsx`, `.css` or `.html`, and is not
   `*.test.tsx`, `*.spec.tsx`, `*.stories.tsx` or under a `__tests__/` folder: the host's rule exactly
   (host @@ -102), with the host's `web/src/` folder now the setting's default. A project whose folders hold no
   matching file never has a screen diff, so its merges skip the check. `is_screen` takes a repo-relative path only.
   `screen_rel <absolute path>` makes one: the root is `git -C <dir> rev-parse --show-toplevel` from the file's own
   folder (the nearest existing folder above it when a Write creates new folders), never the session's working
   folder; it prints the path with `<root>/` taken off, and the root on a second line; a path in no checkout prints
   nothing (not screen code). The merge's `$MERGE_TOUCHES` paths are repo-relative already (`git diff --no-relative
   --name-only`, `:223`). The content tripwire receives absolute paths (`hooks/__tests__/edit-content-tripwires.test.sh:15`,
   `:69`; `SCOPE_PATH`, `hooks/edit-content-tripwires.sh:228`): it passes `screen_rel`'s path to `is_screen` and to the
   `Placeholder:` file match, reads the unit (the root's folder name) and main (`pp_project <root>`) from that root,
   and keeps the absolute `FILE_PATH` for every read and message.
2. **`screenPaths` (setup key).** `--screen-paths '<folder>[,<folder>]'` (an empty value writes `[]`) in
   `scripts/setup.sh` (`TAKES`, `old`, flag parse, the writer), kept on a re-run. `skills/setup/SKILL.md` asks "Screen
   code": `web/src/` (the default; recommended when it exists) | None | Type my own. None: setup prints "no screen
   paths: the merge's screen and placeholder checks are skipped". Docs: `docs/setup-questions.md`, `README.md:112`,
   `docs/configuration.md:63`.
3. **`check_screens` (host @@ -102, exact apart from the prefixes).** In `scripts/merge-unit-local.sh`, defined
   before step 1's checks and called after `no_holds "step 1 preconditions"` (`:241`): no prefix, or no
   `$MERGE_TOUCHES` path that `is_screen`: return, print nothing. Else read `## Screenshots` of
   `$WT/.claude/briefs/$UNIT-evidence.md`: rows `- side-by-side: <mockup> | <screenshot>`, `- screenshot: <path>`,
   `- none: no visual change: <reason>`; every named file (a mockup may be an `http(s)` URL, not checked; relative to
   the worktree or absolute) must be a non-empty file. No row: `fail "step 1 preconditions" "screen code changed
   (<first path>) and <evidence> has no ## Screenshots side-by-side list, screenshot or no-visual-change row"`; a
   missing file: `"<evidence> names <path>, which does not exist"`; pass prints `STEP 1 screens: <n> rows` or `STEP 1
   screens: no visual change declared: <reason>`. Catches: a GO'd screen change with nothing a person can look at
   (the issue); nothing reads screen evidence today.
4. **Template (host @@ -22).** `templates/_builder-brief-template.md` after `:32`: a unit that changes screen code
   (the project's `screenPaths`) writes `## Screenshots` in its evidence file before the closing pass, one row each
   as above; screenshots go at absolute paths outside the worktree (an untracked image inside it is refused at step 1
   as untracked code, `merge-unit-local.sh:211-214`). Catches: a GO'd unit refused at merge, a fix round and a pass.

Produces: `screen_prefixes`, `is_screen`, `screen_rel`; the `screenPaths` key; step 1's screen refusal and pass lines.
Consumes: `MERGE_TOUCHES` (`:223`), `fail` (`:86`), `WT`, `UNIT`.
Existing consumers of a changed contract: `setup.sh`'s writer (the key rides with the answers); every merge
(non-screen merges print nothing new; a project with `"screenPaths": []` is unchanged).
Size: screen-code.sh 55, check_screens 32, setup.sh 8, SKILL.md 6, docs 5, template 6, tests 87.

Acceptance tests (`scripts/__tests__/merge-unit-local-screens.test.sh`, new, sourcing
`fixtures/merge-unit-local-setup.sh`; the fixture project's commandeck.json has no `screenPaths`, so the default
applies, unless a case sets one): "with the default, a screen diff under web/src with no evidence is refused"; "a set
folder replaces the default" (`"screenPaths": ["app/ui/"]`: a screen diff under `app/ui/` with no evidence is
refused, one under `web/src/` merges); "with screenPaths empty a screen diff merges unchecked"; "a logic file in screen
folders merges with no screens line" (`web/src/lib/x.ts`); "a test file under screen folders merges"
(`web/src/__tests__/y.test.tsx`); "a side-by-side row whose files exist merges"; "a named missing screenshot is
refused"; "a screenshot row whose file exists merges"; "a no-visual-change row merges and prints its reason"; "a
no-visual-change row with no reason is refused".
`hooks/__tests__/edit-content-tripwires.test.sh` (C5's fixture project): "an absolute screen path is screened"
(`file_path` `<fixture worktree>/web/src/X.tsx`, the hook run from the worktree root, `new_string` `<p>Coming
soon</p>`: exit 2); "a session started in a subdirectory still screens the file" (the same payload, the hook run from
`<fixture worktree>/web`: exit 2, the message naming the absolute path).

Break: scripts/__tests__/merge-unit-local-screens.test.sh -- with the default, a screen diff under web/src with no evidence is refused -- scripts/merge-unit-local.sh the check_screens call
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a set folder replaces the default -- hooks/lib/screen-code.sh screen_prefixes reads the set folders (replaced by the default alone)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a named missing screenshot is refused -- scripts/merge-unit-local.sh the file-exists test in check_screens
Break: hooks/__tests__/edit-content-tripwires.test.sh -- a session in another checkout screens the file by the file's checkout -- hooks/lib/screen-code.sh screen_rel's root (replaced by the working folder's)
(Build note: the subdirectory case shares the file's root, so it cannot catch this break; the added case, run from u2
on u1's file, does.)

### C5 -- #398: no unrequested placeholder UI, at edit, review and merge (~280 lines)

1. **What placeholder UI is (one home, `hooks/lib/screen-code.sh`).** `PLACEHOLDER_COPY`, case-insensitive:
   `coming soon`, `not available yet`, `not yet available`, `available soon`, `in a later update`, `in a later
   release`, `coming in a later`. `ALWAYS_DISABLED` is a control attribute, not a word: `always_disabled_lines`
   (an awk program in POSIX awk, so BSD awk runs it; C8's sweep covers its print lists) reads a text on stdin (a file
   at the branch tip, or a plan or batch) and prints, once per occurrence, the number of each line holding a
   single-line opening tag with a constant `disabled` attribute. Fix round 4 (class jsx-context, found in passes 1 to
   4; main's answers answer-1793068128-36463 and answer-1793068518-93805) replaces the character scanner of rounds 2
   and 3 with this fixed pattern. The fence for the class: each line is judged alone, so no construct on one line can
   add or hide a control on another, and no lexical context (string, comment, template, JSX text, generic) is
   tracked. On each line, left to right:
   - A tag is `<NAME` then attributes then `>` (or `/>`), all on that line. `NAME` is a lowercase HTML element that
     takes `disabled` (`button`, `input`, `select`, `textarea`, `fieldset`, `optgroup`, `option`) or any capitalised
     component name (`Button`, `IconButton`, `Menu.Item`). Between the name and the `>`, an attribute value is read
     whole as `"..."`, `'...'` or one `{...}` with no braces inside it, so the `>` of `=>` in `onClick={() => save()}`
     and the `>` in `title="a > b"` end nothing; any other `<`, `>`, quote or brace ends the try at that `<`. Every
     `<` on the line starts its own try, one inside another tag's value too (`icon={<Button disabled />}`); a tag's
     own `disabled` is read with its values replaced, so a control inside a value counts once, for itself.
   - Inside a tag, each `disabled` attribute name (white space before it) counts when it is bare (the next thing past
     white space is `/`, `>` or another attribute, not `=`), `={true}` (white space allowed around the `=` and inside
     the braces) or `=` a quoted string (a string literal disables in HTML and React alike).
   - Not matched: `disabled={<anything else>}` (behaviour), `data-disabled`, `disabled-x`, `:disabled`, `.disabled`,
     every `disabled` outside such a tag (`const disabled = busy;`, a destructured `disabled`), and a lowercase tag
     that is no control (`<div disabled>`). Two controls on one line are two occurrences (the line printed twice).
   - Stated ceilings (Accepted failure mode 10, and a plain comment on the function): a tag split over lines (a
     `disabled` on its own line, a value on a later line, a multiline `{...}` value), a value with nested braces, type
     arguments on the tag (`<Select<O> disabled>`) and an unquoted HTML value (`disabled=disabled`) are missed; a
     single-line control spelled in a string, template or comment of a screen file is refused, as is a comment
     between `disabled` and its `=`; a comment inside `{true}` is missed.
   - No flags: TSX, `.html` screen files, plans and batches are read the same way. The scanner keeps nothing between
     runs and nothing between lines.
2. **What "requested" means (Decision 13).** A line in the unit's plan as committed on local main (each
   `.claude/plans/<file>.md` the unit brief's `## Plan` section names, read with `git show main:<path>`) or in main's
   rulings file (`<main>/.claude/briefs/<unit>-main-rulings.md`), of the form `Placeholder: <screen file> | <complete
   source line> | <why>`, with a non-empty why. The middle field is the complete added source line, compared with the
   added line after both have leading and trailing whitespace trimmed, by equality: never a substring, so naming
   `disabled={true}` approves no control. Each `Placeholder:` line approves one added line: two identical added lines
   need two `Placeholder:` lines (the merge counts them). A line holding an approved control and an unapproved one is
   a different complete line, so it is refused, and its entry lists every occurrence on it. `placeholder_requested
   <file> <line> <unit> <worktree> <main>` answers it; the refusal prints the exact line to copy into a `Placeholder:`
   line.
3. **Edit time (the content tripwire).** `hooks/edit-content-tripwires.sh`, beside the placeholder-comment rule
   (`:259-277`): every added line of a file `is_screen` (C4's `screen_rel` path) matching `PLACEHOLDER_COPY` and not
   requested is listed (each such line, not the first only) in `BLOCKED: placeholder copy in <absolute file>: "<line>".
   Build only what the plan asks for; a mockup element the plan does not build is left out and sent to main as a
   question. Allowed only when the plan or main's rulings name the complete line: Placeholder: <file> | <complete source
   line> | <why>`. The unit is the folder name of the file's worktree root and main is `pp_project <root>`'s
   `PP_PROJECT_DIR` (`hooks/lib/project.sh:7-19`), both from `screen_rel`, never the session's working folder. The
   edit block checks copy only; always-disabled controls are the merge's (one home for their refusal and its
   per-line approval count). Strict tier, as the hook is (L4).
4. **Merge time.** `check_placeholders` in `scripts/merge-unit-local.sh`, called after `check_screens`: for every
   added line (`git diff -U0 <merge-base> <branch>`) of a file `is_screen`, each `PLACEHOLDER_COPY` match and each
   `always_disabled_lines` occurrence (run on `git show <branch>:<file>`, kept where its line number is an added one)
   is an occurrence; every occurrence on a line that is not requested is one entry `<file>:<line number>: <match> in
   <trimmed line>`; any entry: `fail "step 1 preconditions" "unrequested placeholder UI (<n>): <entries, at most 20,
   then '... and <k> more'>; build it, remove it, or have the plan or main's rulings name the complete line on a
   'Placeholder: <file> | <complete source line> | <why>' line"`. Catches: always-disabled controls and placeholder
   copy the review passed (the issue's 21 controls); no step reads them today, and the edit block runs in the strict
   tier only.
5. **Review.** `scripts/builder-codex-pass.sh`: new `PLACEHOLDER_UI='Report as P1 (class: placeholder-ui) a control,
   message or screen the diff adds that is disabled for good, a stub, or says it comes later ("coming soon", "not
   available yet", "in a later update"), unless the plan or main'"'"'s rulings name it on a Placeholder: line.'`
   beside `DATA_DESIGN` (`:138`), appended to `FOCUS_REVIEW` (`:141`) and to each adversarial and one-reviewer focus
   (`:924`, `:1404`). Catches: placeholder UI a reviewer reads as finished work (the issue's two missed passes).
6. **Rule.** `templates/_builder-brief-template.md`, after C4's bullet: "Build only what the plan asks for. Never add a
   disabled, stub or 'coming soon' control or message to match a mockup; a mockup element the plan does not build is
   left out, and you send main the question. A placeholder the plan wants is named on a `Placeholder: <file> | <exact
   text> | <why>` line."
7. **Brief check.** `scripts/plan-check.sh` prints, for each line of the plan or the batch that matches
   `PLACEHOLDER_COPY` or that `always_disabled_lines` names (run on the whole plan and the whole batch, so a literal
   always-disabled control written as context, `<Button disabled={true}>Export</Button>`, is flagged, and prose that
   says "disabled" outside a tag is not) and is not a `Placeholder:` line, `FLAG: <label> line <n> describes
   placeholder UI: an open problem, not a fact: plan its removal, name it on a Placeholder: line, or file it`, on
   stderr, exit unchanged; the
   launcher and the judge launch pass it through. The plan-judge prompt (`seat.sh:429`) gains: "A plan or batch line
   that describes existing placeholder UI (a disabled control, 'coming soon' copy) as context is a finding: an open
   problem until the plan removes it or names it on a `Placeholder:` line." Catches: main recording an earlier
   placeholder as a plain fact in the next brief (the issue).

Produces: `PLACEHOLDER_COPY`, `always_disabled_lines`, `placeholder_requested`; the tripwire's block; the merge refusal; the
review P1 class `placeholder-ui`; plan-check's `FLAG:` lines; the `Placeholder:` line contract.
Consumes: C4's `is_screen`, `screen_rel` and `screen_prefixes`; the brief's `## Plan` section; local main; main's rulings file.
Existing consumers of a changed contract: `FOCUS_REVIEW` and the adversarial focus feed every reviewer prompt
(`builder-codex-pass.test.sh:139-142` greps the Data design sentence in prompts: unchanged); plan-check's stderr
(the launcher and seat.sh print it; no script parses it); the tripwire's rule table (`edit-content-tripwires.test.sh`
cases unchanged).
Size: screen-code.sh 80, merge 38, tripwire 28, review 6, template 5, plan-check 12, seat 1, tests 108.

Acceptance tests:
- `hooks/__tests__/edit-content-tripwires.test.sh` (strict tier, a fixture project with `screenPaths` and a unit
  worktree whose brief names its plan on main): "placeholder copy in screen code is refused, naming the file and the
  line"; "the same copy is allowed when the plan names its complete line on a Placeholder line"; "copy named only by a
  substring of its line is refused" (`Placeholder: web/src/X.tsx | Coming soon | why`, added `<p>Coming soon</p>`:
  exit 2); "placeholder copy outside screen code passes"; kept: "a placeholder comment is still caught" (the existing
  rule's case).
- `scripts/__tests__/merge-unit-local-screens.test.sh`: "an unrequested always-disabled control is refused and listed"
  (two controls: both entries in the message); "a disabled control the plan names merges" (`Placeholder:
  web/src/pages/X.tsx | <Button disabled={true}>Export</Button> | its target no longer exists`, the added line
  indented); "an approved and an unapproved control in one file: only the unapproved one is refused" (that
  `Placeholder:` line; added lines `<Button disabled={true}>Export</Button>` and `<Button
  disabled={true}>Delete</Button>`: refused, one entry, naming Delete's line); "an approved and an unapproved control on
  one line are refused" (the same `Placeholder:` line; added `<Button disabled={true}>Export</Button><Button
  disabled={true}>Delete</Button>`: refused, two entries for that line); "a bare-substring approval approves nothing"
  (`Placeholder: web/src/pages/X.tsx | disabled={true} | why`, added `<Button disabled={true}>Export</Button>`:
  refused); "a dynamic disabled prop merges" (`disabled={busy}`); "a variable named disabled and a dynamic prop merge"
  (added `const disabled = busy;` then `<Button disabled={disabled}>Export</Button>`, a valid screenshot row, no
  `Placeholder:` line: merges, no placeholder entry); "a disabled attribute on its own line inside a tag is a stated
  miss" (`<Button` / `  disabled` / `>Export</Button>` on three added lines: merges, no entry; fix round 4 flipped it
  from refused, Accepted failure mode 10); "a disabled control after an
  arrow-function prop is refused" (added `<Button onClick={() => save()} disabled={true}>Export</Button>` in
  `web/src/pages/X.tsx`, a valid screenshot row, no `Placeholder:` line: refused, one entry naming that line); "a
  disabled control after a quoted > is refused" (added `<input title="a > b" disabled />`, the same evidence: refused,
  one entry); "placeholder copy main's rulings name merges".
- `scripts/__tests__/builder-launch-resume-launch-line.test.sh`: "a plan that describes placeholder UI as context is
  flagged and still launches"; "a batch line naming a literal disabled control is flagged" (the batch line `Context:
  <Button disabled={true}>Export</Button> already ships as a layout stub.`: one `FLAG:` line naming the batch and that
  line, exit unchanged); "a plan's Placeholder line is not flagged".
- `scripts/__tests__/builder-codex-pass.test.sh`: "the review prompt names placeholder UI as P1" (beside `:139-142`).

Break: hooks/__tests__/edit-content-tripwires.test.sh -- placeholder copy in screen code is refused, naming the file and the line -- hooks/edit-content-tripwires.sh the placeholder-copy block
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- an unrequested always-disabled control is refused and listed -- scripts/merge-unit-local.sh the check_placeholders call
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a disabled control the plan names merges -- hooks/lib/screen-code.sh placeholder_requested reads local main's plan (replaced by the worktree's own copy, which the test's Builder edited)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a bare-substring approval approves nothing -- hooks/lib/screen-code.sh placeholder_requested's complete-line equality (replaced by a substring test: the approval's middle field found inside the added line)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a disabled control after an arrow-function prop is refused -- hooks/lib/screen-code.sh always_disabled_lines' whole `{...}` value in the tag pattern (removed, so the `>` of `=>` ends the try)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- an approved and an unapproved control on one line are refused -- scripts/merge-unit-local.sh check_placeholders' per-occurrence loop (replaced by the first match on a line)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- a variable named disabled and a dynamic prop merge -- hooks/lib/screen-code.sh always_disabled_lines' value rule (a `{...}` value counts only as exactly `{true}`; replaced by every `{...}` value read as true)
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- a batch line naming a literal disabled control is flagged -- scripts/plan-check.sh the always_disabled_lines call in the brief check

### C6 -- #387: recorded holds are cut, unexplained idle is shown apart (~210 lines)

1. **`scripts/unit-hold.sh` (new, host `unit-hold.sh`).** `unit-hold.sh <unit> hold|release '<one-line reason>'`
   appends one `jq -nc` row `{unit, event, at, reason}` to `<main>/.claude/metrics/unit-holds.jsonl`
   (`COMMANDECK_UNIT_HOLDS` overrides the path, the test seam). One `>>` append of one line under 4 KB (a longer row is
   refused, exit 2); when the file's last byte is not a newline the row starts on a fresh line (the host's pass-4 fix:
   a torn append must not swallow the row). A failed append exits 1 naming the file. Bad arguments: usage, exit 2.
2. **`collect.py` (host @@ -51 to -955).** `HOLDS = None` beside `DECISIONS` (`:52`); `holds_for(path, unit)` beside
   `decisions_for` (`:254`): append-only pairing (a hold opens, the unit's next release closes, a stray release is
   ignored, an open hold runs to the review's end, a line that is not JSON is skipped). After the decision cuts
   (`:765`): `busy_spans` = every Codex run and every background job of any session (start to its `woken` end, or the
   review's end); each hold window minus every busy span is appended to `cuts` with reason `hold`. The cut paint
   (`:811`) paints a `hold` window over `('none', 'gap') + IDLE` only. Then a run of `none` labels outside every Codex
   run lasting `WAIT_ON_OWNER` or more is painted `unexplained` and listed (start, end, seconds). `cut_in`'s twin
   `unexplained_in`; the stage init (`:674`) gains `unexplained_s=0`; the clock loop (`:829`) counts `unexplained` like
   `cut`; `waiting` (`:893`) divides by the clock less both; the result gains `unexplained`, `unexplained_s`, and each
   pass `unexplained_s` (`:916-917`); the printout gains its line (`:937`).
3. **`render.py` (host @@ -22, -336, -523).** `took()` (`:25`) subtracts `unexplained_s` too (absent in an old
   result.json: 0); an "Unexplained idle" box after the cut box (`:347`) lists From, To, Length; it joins the time box
   (`:543`).
4. **Docs.** `templates/main-session.md`: "A unit parked on purpose is recorded with `unit-hold.sh <unit> hold|release
   '<reason>'`, so the build review cuts the parked time." `skills/worktreereview/SKILL.md`: one line on hold cuts and
   unexplained idle.

Produces: `unit-hold.sh` CLI and `unit-holds.jsonl` rows; `result.json` keys `unexplained`, `unexplained_s` (per
stage, per pass, whole); cut rows with reason `hold`. Consumes: `main_checkout`, `paint`, `runs`, every session's
`tools` and `woken`, `WAIT_ON_OWNER`.
Existing consumers of a changed contract: `render.py` (reads the new keys with defaults); the dashboard does not read
`result.json` (`rg -n 'result.json' scripts/dashboard*` is empty, 2026-10-26); `worktreereview.test.sh`'s existing
figures (a run with no hold and no gap of 120 s with no session open renders as before: kept).
Size: unit-hold.sh 27, collect.py 60, render.py 8, tests 110, docs 4.

Acceptance tests (`scripts/__tests__/worktreereview.test.sh`; every hold row is written by running
`scripts/unit-hold.sh` itself with `COMMANDECK_UNIT_HOLDS` naming the fixture file, which then feeds `collect.HOLDS`):
"a hold between two plan sessions is cut and listed" (the stage equals the sessions); "a gap with no record is
unexplained idle, not stage time"; "open hold runs to the end"; "a Codex run inside a hold stays work" (sessions
10:00-10:01 and 10:10-10:11, hold 10:01-10:10, Codex run 10:03-10:05: hold cut 420 s, the run's 120 s in the stage
figure, no unexplained row); "a failed hold append exits 1 and cuts nothing" (the holds file in a read-only folder);
"a release after a torn append still closes the hold"; "a hold is cut around every background job, whichever session
shows the wait" (the host's three orderings); "an old result.json with no unexplained keys still renders".

Break: scripts/__tests__/worktreereview.test.sh -- a Codex run inside a hold stays work -- skills/worktreereview/scripts/collect.py the subtraction of busy spans from each hold window
Break: scripts/__tests__/worktreereview.test.sh -- a hold between two plan sessions is cut and listed -- scripts/unit-hold.sh the whole body replaced by exit 0
Break: scripts/__tests__/worktreereview.test.sh -- a release after a torn append still closes the hold -- scripts/unit-hold.sh the fresh-line lead

### C7 -- #397: helper models are routing settings, every worker pane runs the guard, Builder, plan-author and fix-round panes enforce them, plan authors may start helpers and judges may not, the review flags helper-less builds (~210 lines)

1. **Routing (one home).** `config/routing.json` `roles.builder` gains `"helpers": {"Explore": "haiku",
   "general-purpose": "sonnet", "debugger": "sonnet"}`; its note says the helpers run on these models. The routing
   validator (`scripts/paths.sh:724-725`) accepts `helpers` on a role: an object whose values match
   `^[a-z][a-z0-9.-]*$`; anything else fails the whole file with `<role> has a bad helpers entry <key>`, as every
   routing fault does.
2. **The guard reads them.** `hooks/agent-model-guard.sh` reads `.roles.builder.helpers` from
   `${COMMANDECK_ROUTING:-<hook dir>/../config/routing.json}` in its one jq call. The enforcing panes are a Builder
   pane, a plan-author pane and a fix round, told apart by the seat marker every seat pane already exports
   (`export COMMANDECK_SEAT=$ROLE`, `scripts/seat.sh:279`; A15): `COMMANDECK_SEAT` is `builder` or starts
   `plan-author`, or it is unset and `COMMANDECK_BUILDER=1` (a Builder pane opened by hand). A fix round is the
   Builder's own pane after `/clear` (`builder-fresh-round.sh:106`, the `fixer` note at `config/routing.json:64-72`),
   so it carries the Builder's marker. The test is one function, `is_helper_pane` in `hooks/lib/helper-pane.sh` (new,
   builtins only), sourced by the guard and by C10's `codex-ask.sh`. In an enforcing pane a call of a type in `helpers` runs as `helpers[type]`
   whatever model it names (today only a Builder's Explore is forced). Every other pane, a plan-judge or reviewer
   seat included even inside a Builder worktree (its `COMMANDECK_SEAT` names its role): a call of a type in `helpers`
   that names no model runs as `helpers[type]`, and a named model runs as named (as today). A call of any other type
   is unchanged in every pane (forks, custom types). A helpers map that cannot be read leaves the call as it is and
   reports it (item 4); the guard never refuses (as today). No environment variable sets a model; the plan-author
   marker is the existing per-pane `COMMANDECK_SEAT`, not a worktree setting, because plan-judge seats work in the
   same planning worktree.
2a. **The standing helper line (the owner's extension).** One sentence, `PP_HELPER_LINE` in `scripts/paths.sh`: "Use
   helper subagents wherever the work allows: general-purpose (runs on the configured Sonnet model) for independent
   build cuts, research and test writing, Explore (runs on the configured Haiku model) for search and proof; this
   pane keeps only cut ordering, cross-cut contracts and final integration." It is appended to the plan-author prompt
   (`seat.sh:420-431`, the `plan-author*` lines) and printed as a bullet of the fix-round hand-off
   (`builder-codex-pass.sh:1812-1815`); `templates/_builder-brief-template.md` carries it word for word in its rules,
   and a test holds the template to the constant. Catches: a pane that does the cuts itself on its own model because
   nothing told it to hand them out (the issue's helper-less builds).
2b. **The build review (the owner's extension).** `collect.py` adds `HELPERLESS_LINES = 300` beside `SHARE_FLOOR`
   (`:50`) and, in the flags (`:895-904`), when `lines_changed` (`:913`) is over it and no helper started: "<n> changed
   lines and no helper agent started (over 300, a build hands cuts to helpers)"; unknown `lines_changed`: no flag.
   `render.py` adds one fact before the per-helper lines (`:258`): "Helpers: <n> started; by model: <model> <count>,
   <spend>; ..." (spend from each helper's `tokens.usd`, as `:258` prints it). Catches: a regression to helper-less or
   Opus helpers, visible on the page (the issue).
3. **Every worker pane runs it (the cause, A4).** `scripts/worktree-setup.sh` registers `agent-model-guard.sh`
   through `run-hook.sh` on `PreToolUse` matcher `Agent|Task` in the worktree's `settings.local.json` on every run,
   not only `--builder`: it runs for every Builder worktree (`builder-launch.sh:369`) and every worker seat's
   (`seat.sh:336`), so the plugin's own builds included. The entry is one of the leaves the script owns: a rerun
   writes it once (`unique`), as the Builder hooks at `:226-250` are. A pane whose Claude Code does not load the
   plugin's `hooks/hooks.json` now runs the guard; one that loads both runs it twice with the same answer (L6).
3a. **Plan authors can start helpers; plan judges and reviewers cannot (the cause of a plan-author pane with no
   helpers).** Today every worker worktree denies `Agent` (`scripts/worktree-setup.sh:129`, written at `:173`), and
   only `--builder` takes it out (`:234`); `seat.sh:336` sets up a planning worktree without `--builder`, so a
   plan-author pane has no `Agent` tool and the model rewrite of item 2 never runs there. A plan judge and a reviewer
   seat run in the same worktree as the plan author or the Builder (`seat.sh:84`: every launch is `WTN=$UNIT`), so
   the worktree settings cannot tell them apart; the denial for them moves into the pane, where routing already
   denies their writing tools:
   - `scripts/worktree-setup.sh`: a worktree whose git dir holds the `commandeck-plan-of` mark is a planning worktree
     (seat.sh writes the mark on a plan seat's first launch, `:328`; `plan-worktree-close.sh --adopt` removes it,
     `:153`, and the Builder's `--builder` run allows `Agent` anyway). A run on a planning worktree takes `Agent` out
     of `permissions.deny` as the Builder branch does, every other denial kept; the same with `--print-settings`, so
     `plan-worktree-close.sh:52`'s comparison reads the same mark and still matches. An unmarked worker worktree
     still denies `Agent`.
   - `config/routing.json`: `"Agent"` is added to the `tools` list of `plan-judge-fable`, `plan-judge-sol.claude`
     and `codex-reviewer.claude`, which `pp_argv` turns into `--disallowedTools Write,Edit,NotebookEdit,Agent`
     (`scripts/paths.sh:876`). A Claude judge or reviewer pane then has no `Agent` tool in any worktree, a Builder's
     included, where today it inherits the Builder's allowance. Codex seats have no `Agent` tool. The validator's
     write rule (`paths.sh:826`) is unchanged.
   - Settled (A17): `--disallowedTools Agent` removes the subagent tool.
   - `docs/configuration.md` (beside C7 item 5's line): plan-author panes may start helpers; judge and reviewer panes
     may not.
4. **A failure is reported, not silent.** The guard: when its jq call fails or the helpers map cannot be read, it
   prints one JSON line (built with `printf`, no jq) carrying `systemMessage` and `additionalContext`:
   "agent-model-guard.sh could not run (<reason>): this call keeps the model it names", and exits 0 (nothing is
   blocked). The runner: `hooks/lib/run-hook.sh`'s no-Bash-4 line (`:19`) becomes the same one line as a
   `systemMessage` JSON object (the plugin's advisory form, `hooks/git-ignore-warn.sh:81`), so the person sees that
   no hook ran instead of a line Claude Code shows only in its transcript view; still exit 0, still one line.
5. **Docs.** `docs/configuration.md:46` and `docs/hooks.md:19` say the models come from `roles.builder.helpers`, that
   every worker pane runs the guard, and that Builder, plan-author and fix-round panes enforce both models. The review already shows each
   helper's model and cost (`render.py:258`, `:179`); a pin test keeps it (the issue: a regression stays visible).

Produces: `roles.builder.helpers`; the enforcing-pane rewrite of a named wrong model; the worktree registration; the
guard's failure line; the runner's `systemMessage` line; `PP_HELPER_LINE` in three places; the review's helper fact
and helperless flag; a planning worktree's settings without the `Agent` denial; `Agent` in the Claude judge and
reviewer `tools` lists.
Consumes: `COMMANDECK_SEAT` (seat.sh:279), `COMMANDECK_BUILDER` (set by `worktree-setup.sh --builder`), the routing
file, `collect.py`'s `helpers` and `lines_changed`, the `commandeck-plan-of` mark, `pp_argv`'s `tools` words.
Existing consumers of a changed contract: `pp_route` and every launch read routing.json through the validator
(a valid file passes unchanged); `agent-model-guard.test.sh` (its non-Builder named-model cases stay; none pins a
Builder general-purpose call); `worktree-setup.test.sh` and `install-lib.sh:368-377` (every worktree's settings gain
one hook entry; A11); `run-hook.test.sh:46-52` (counts the line's text once and one line: both still hold);
`seat-plan-marker.test.sh:30-38` (its prompt patterns still match: the line is appended); the review's `flags` list
(`render.py:248` prints every flag; a new one is one more line); `worktreereview.test.sh`'s existing fixtures (each
over 300 lines with no helper would now be flagged: the Builder checks which do and gives them a helper or a smaller
diff only where a case pins the flag list, A16); the settings and argv item 3a changes: `plugin.test.sh:92` (pins
the Fable judge's tools as exactly `Write,Edit,NotebookEdit`: flips to `Write,Edit,NotebookEdit,Agent`),
`builder-codex-pass.test.sh:168` (`grep -cx 'Write,Edit,NotebookEdit'` on the headless reviewer's argv: flips to the
four-tool word), `seat-launch.test.sh:132`, `:138` (substring greps: still match), `plugin-option.test.sh:165-186`
(owner overlays checked by the write rule only: unchanged), `plan-worktree-close.sh:52` (compares with the same
generator: unchanged), `install-lib.sh:368-377` (prints Builder settings only: unchanged).
Size: routing 6, paths.sh 8, guard 26, seat.sh 1, hand-off 1, template 2, collect.py 6, render.py 5, worktree-setup
10, run-hook 2, tests 134, docs 8.

Acceptance tests:
- `hooks/__tests__/agent-model-guard.test.sh`: "a Builder's general-purpose call naming opus runs as Sonnet"; "a
  plan-author pane's general-purpose call naming opus runs as Sonnet and its Explore naming sonnet as Haiku"
  (`COMMANDECK_SEAT=plan-author`); "a fix round in the Builder's pane enforces both models" (the env a fix round has:
  `COMMANDECK_SEAT=builder`, `COMMANDECK_BUILDER=1`, after `/clear`); "a plan-judge seat in a Builder worktree keeps
  its named model" (`COMMANDECK_SEAT=plan-judge-sol`, `COMMANDECK_BUILDER=1`, general-purpose naming opus: unchanged);
  "a named model outside these panes runs as named" (no seat, no Builder flag: opus stays opus; an unnamed one is
  filled); "a changed routing setting changes both helper models" (`COMMANDECK_ROUTING` naming a copy with Explore sonnet and
  general-purpose haiku); "a reviewer-type call naming opus is unchanged in a Builder pane"; "an unreadable routing
  file changes nothing and is reported" (valid JSON with `systemMessage`, exit 0); "a call already on its configured
  model passes unchanged" (the second run); kept: every existing case.
- `scripts/__tests__/worktree-setup.test.sh`: "a Builder worktree created the normal way runs Explore on Haiku and
  general-purpose on Sonnet" (runs `worktree-setup.sh <wt> --builder`, takes the `Agent|Task` command from the
  written `settings.local.json`, runs it with the settings' env on an Explore payload and on a general-purpose payload
  naming opus: `haiku`, `sonnet`); "a worker worktree registers the model guard too"; "a rerun registers it once";
  "a planning worktree's settings allow helpers" (a worktree whose git dir holds `commandeck-plan-of`, set up the way
  `seat.sh:336` does, no `--builder`: `.permissions.deny` lacks `Agent` and still holds `WebSearch`, and the
  registered guard rewrites a general-purpose call naming opus to `sonnet` with `COMMANDECK_SEAT=plan-author`); "an
  unmarked worker worktree still denies helpers" (`Agent` in `.permissions.deny`); "a planning worktree's printed
  settings match the written ones" (`--print-settings` equals the file as JSON, the `plan-worktree-close.sh`
  comparison).
- `scripts/__tests__/seat-launch.test.sh` (light, after `:60`): "a plan-author seat's pane can start helpers" (the
  record's `cmd=` carries no `Agent` in any `--disallowedTools` word; its worktree settings are the
  `worktree-setup.test.sh` case above); "a Claude plan judge in the same planning worktree cannot start helpers" (`plan-judge-fable` and
  `plan-judge-sol` on claude: `cmd=` carries `--disallowedTools Write,Edit,NotebookEdit,Agent`).
- `scripts/__tests__/builder-codex-pass.test.sh`: "the headless Claude reviewer cannot start helpers" (the flipped
  `:168` check: its argv holds the word `Write,Edit,NotebookEdit,Agent`).
- `hooks/__tests__/run-hook.test.sh`: "with no Bash 4 the runner's line is a message the person sees" (one line, valid
  JSON, `.systemMessage` holds the old text, exit 0).
- `scripts/__tests__/worktreereview.test.sh`: "the review names each helper's model and cost"; "the review prints
  helper count and spend by model"; "a build over 300 changed lines with no helper is flagged"; "a build of 300 lines
  with no helper is not flagged"; "a build over 300 lines with a helper is not flagged".
- `scripts/__tests__/seat-plan-marker.test.sh`: "the plan-author prompt carries the helper line"; "the Builder brief
  template carries the helper line word for word".
- `scripts/__tests__/builder-codex-pass-fresh-round.test.sh` (light, after `:99`, before the BSD-awk case): "the
  fix-round hand-off carries the helper line".
- the routing validator: "a helpers entry that is not a model name fails the routing file" in the test that pins
  `has unknown field` (A11).

Break: hooks/__tests__/agent-model-guard.test.sh -- a Builder's general-purpose call naming opus runs as Sonnet -- hooks/agent-model-guard.sh the Builder-pane enforcement
Break: scripts/__tests__/worktree-setup.test.sh -- a Builder worktree created the normal way runs Explore on Haiku and general-purpose on Sonnet -- scripts/worktree-setup.sh the guard registration
Break: hooks/__tests__/agent-model-guard.test.sh -- an unreadable routing file changes nothing and is reported -- hooks/agent-model-guard.sh the failure line
Break: hooks/__tests__/agent-model-guard.test.sh -- a plan-author pane's general-purpose call naming opus runs as Sonnet and its Explore naming sonnet as Haiku -- hooks/agent-model-guard.sh the plan-author arm of the enforcing-pane test
Break: hooks/__tests__/agent-model-guard.test.sh -- a plan-judge seat in a Builder worktree keeps its named model -- hooks/agent-model-guard.sh the seat-before-worktree order of the enforcing-pane test
Break: scripts/__tests__/worktreereview.test.sh -- a build over 300 changed lines with no helper is flagged -- skills/worktreereview/scripts/collect.py the helperless flag
Break: scripts/__tests__/worktree-setup.test.sh -- an unmarked worker worktree still denies helpers -- scripts/worktree-setup.sh the plan-of mark test (replaced by true)
Break: scripts/__tests__/seat-launch.test.sh -- a Claude plan judge in the same planning worktree cannot start helpers -- config/routing.json the Agent entry in plan-judge-fable's tools

### C8 -- #393, #395, #390: the BSD-awk step, bash-only paths.sh, the stale snapshot pin (~55 lines)

1. **#393.** `scripts/builder-codex-pass.sh:1806`: `n[c] == 1 ? "" : "s"` becomes `(n[c] == 1 ? "" : "s")`. BSD awk
   refuses a comparison unparenthesized in a print list (A1). The sweep of every `print`/`printf` argument list in
   `scripts`, `hooks` and `skills` shell files found this one site (A1).
2. **#395 (host @@ -12).** `scripts/paths.sh`, after the header comment (`:18`), before `pp_slug`: `[ -n
   "${BASH_VERSION:-}" ] || { echo "paths.sh: source this from bash; this shell is not bash" >&2; return 1
   2>/dev/null || exit 1; }`, with a one-line why. Supporting zsh is rejected: the other 1,500 lines are Bash 4.
3. **#390 (no twin).** A pin through the plugin's one snapshot reader, with the issue's own input.

Produces: the paths.sh refusal line. Consumes: nothing new.
Existing consumers of a changed contract: every script that sources paths.sh runs under bash (`#!/usr/bin/env bash`,
`run-hook.sh` execs bash): unchanged.
Size: awk 1, tests 25; paths.sh 2, test 10; units pin 15.

Acceptance tests:
- `scripts/__tests__/builder-codex-pass-fresh-round.test.sh`: "no awk print list in the shell scripts holds an
  unparenthesized comparison" (the A1 sweep as a `grep -rnP` check, every host); last in the file, "a NO-GO pass under
  BSD awk prints no awk error and hands the fix round over" (a folder whose `awk` links `/usr/bin/awk` first on PATH;
  runs where `/usr/bin/awk --version` prints `awk version`, else prints `note: no BSD awk here` and counts nothing, L2).
- `scripts/__tests__/project-main.test.sh` (after :57): "sourced from a non-bash shell" (zsh, else dash, `-c '.
  <paths.sh>'` from outside the scripts folder: rc 1 and exactly the refusal).
- `hooks/units-sources.test.tsx`: "a stale snapshot shows its age beside its rows" (`{"updatedAt":
  "2026-10-26T14:00:00Z", "projects": {"p": {"units": {"inFlight": [{"unit": "u", "stage": "building"}]}}}}` read at
  15:00 for project `p`: `staleMin` 60, the row's stage `building`, and `paneLines` shows `dashboard data is 60 min
  old`).

Break: scripts/__tests__/project-main.test.sh -- sourced from a non-bash shell -- scripts/paths.sh the BASH_VERSION refusal

### C10 -- #399: a read-only Codex helper for Builders, planners and fix rounds (~335 lines)

1. **`scripts/codex-ask.sh` (new).** `codex-ask.sh [--timeout <s>] '<question>'` (or the question on stdin when the
   argument is `-`). Sources `paths.sh` and `hooks/lib/helper-pane.sh`.
   - Who: `is_helper_pane` (C7 item 2: a Builder pane, a plan-author pane, a fix round) or exit 2 `REFUSED:
     codex-ask.sh is for Builder, plan-author and fix-round panes; this pane is <COMMANDECK_SEAT>`, no Codex call.
   - Which Codex: the review pass's own route, `pp_route codex-reviewer` (`RT_MODEL`, `RT_EFFORT`): no new setting.
     A route whose agent is not codex (`codexReviewerAgent=claude`) is exit 2 `REFUSED: the review passes run on
     Claude here, so there is no Codex helper`.
   - The runner the passes use: `pp_codex_retrust`, then, as the sign-in probe runs it (`builder-codex-pass.sh:1305`),
     `(cd <a fresh mktemp -d folder> && PATH="$PP_SCRIPTS/codex-no-helpers:$PATH" timeout -k 2 <s> codex exec --ephemeral
     --skip-git-repo-check -s read-only -m "$RT_MODEL" -c "model_reasoning_effort=\"$RT_EFFORT\"" -o <answer file>
     "<prompt>") </dev/null 2><stderr file>`. The sandbox is always `read-only`; no option changes it. The working
     folder is outside the repository, so Codex never discovers the repository's `.codex/config.toml`, its project
     hooks or rules, trusted or not (the repository's Codex config is not trusted because it is never read); the
     read-only sandbox still reads the worktree by absolute path (A18). `codex-no-helpers` turns off the home's
     helper servers, as for a pass.
   - The prompt: "You are a read-only helper for the repository at <worktree root>. Read it by absolute path; you
     cannot write, and must not try. Answer in at most 6000 characters, plain text. Question: <question>".
   - Bounds: `--timeout` default 300, an integer 1-1800, else exit 2 with the usage line. The deadline is TERM at
     `<s>` seconds and KILL 2 s later (`timeout -k 2`; GNU timeout signals its own process group, and
     `codex-no-helpers` `exec`s Codex, so Codex is the process signalled), so a call ends within `<s>` + 2 s even when
     Codex ignores TERM (A19). The answer printed is at most 6000 bytes; a longer one prints its first 6000 bytes and
     a last line `codex-ask: answer cut at 6000 of <n> bytes`.
   - The model that answered: the first `model: <id>` line Codex prints in its stderr header (A18: `--json` events
     carry no model). None found is a failure (below), never `unknown`.
   - Output: first line `codex-ask: model <model>, <secs> s`, then the answer; exit 0 only with a non-empty answer and
     a model read from the header.
   - Fails loudly, exit 1, one line on stderr and nothing on stdout, checked in this order: rc 124 (Codex stopped on
     TERM) `codex-ask: TIMEOUT: no answer within <s> s`; rc 137 with `$SECONDS` at least `<s>` (Codex ignored TERM and
     the grace's KILL ended it) `codex-ask: TIMEOUT: no answer within <s> s; Codex ignored TERM and was killed after
     the 2 s grace`; any other non-zero rc `codex-ask: FAILED: Codex exited <rc>: <its last stderr line>`; rc 0 with an
     empty answer file `codex-ask: FAILED: Codex returned an empty answer`; rc 0 with an answer and no `model:` line in
     the stderr header `codex-ask: FAILED: Codex printed no model: header on stderr, so the model that answered is not
     known; the answer is not used`. `TIMEOUT:` is the timeout's own word: no other failure prints it.
   - Record: one `>>` append of one JSON line under 4 KB to `<main>/.claude/metrics/codex-helper.jsonl` (`PP_MAIN`):
     `{"unit": <worktree folder name>, "seat": <COMMANDECK_SEAT or builder>, "model" (null when none was read),
     "start", "secs", "outcome": "answered"|"timeout"|"killed"|"failed"|"empty"|"no-model", "bytes"}`, the torn-line
     rule of C6's `unit-hold.sh` (a fresh line when the last byte is not a newline). A failed append prints
     `codex-ask: warning: call not recorded in <file>` on stderr and keeps the exit code.
2. **Allowed in worker worktrees.** `scripts/worktree-setup.sh`'s allow list gains `Bash(bash <scripts>/codex-ask.sh:*)`
   on every run, so the auto-mode classifier never stops a helper call; the script itself refuses judge and
   reviewer panes (item 1).
3. **Instructions.** `PP_HELPER_LINE` (C7 item 2a) gains one sentence: "For a search, a trace or a second opinion you
   may also ask Codex, read-only: bash <plugin scripts>/codex-ask.sh '<question>' (it cannot edit; writing stays with
   Sonnet helpers)." The constant's three readers (the plan-author prompt, the fix-round hand-off, the Builder brief
   template) carry it; seat.sh and the hand-off print the scripts folder in place of `<plugin scripts>`, and the
   template keeps the placeholder, so the word-for-word test compares the line with the placeholder in it.
4. **Build review.** `collect.py` adds `codex_helpers_for(<main>/.claude/metrics/codex-helper.jsonl, unit)` beside
   `holds_for` (non-JSON lines skipped, other units' rows skipped); `render.py`'s helper fact (C7 item 2b) adds
   "Codex helper: <n> calls, <secs> s, <k> failed; by model: <model> <n>; ...", or "Codex helper: none" (every
   outcome but `answered` counts as failed; a row with a null model counts under `none read`). The
   helperless flag counts Claude helpers only: a Codex helper cannot take a cut.
5. **Docs.** `docs/configuration.md` (beside C7's helper lines) and `README.md`'s helper sentence: the Codex helper,
   read-only, the reviewer's model, the timeout and cap, where calls are recorded.

Produces: `codex-ask.sh` CLI, its output and failure lines; `codex-helper.jsonl` rows; the helper line's Codex
sentence; the allow entry; the review's Codex helper fact.
Consumes: `is_helper_pane` (C7), `pp_route codex-reviewer`, `pp_codex_retrust`, `codex-no-helpers/codex` (its
`exec`), GNU `timeout -k` (A19), `PP_MAIN`, `PP_HELPER_LINE`'s readers.
Existing consumers of a changed contract: `PP_HELPER_LINE`'s readers and C7's tests (the template word-for-word test
and "the plan-author prompt carries the helper line" read the new constant: the Builder updates the template in the
same commit); `worktree-setup.test.sh`'s allow-list checks (a pinned exact list flips to include the entry, A11's
run); `plan-worktree-close.sh:52` (same generator: unchanged); the review's helper fact (C7's new line, extended).
Size: codex-ask.sh 105, worktree-setup 2, paths.sh 2, template 1, collect.py 16, render.py 6, docs 6, codex-ask
test 164, worktreereview 18, seat-plan-marker 6, worktree-setup test 6, CHANGELOG 2.

Acceptance tests:
- `scripts/__tests__/codex-ask.test.sh` (new; a stub `codex` first on PATH after `codex-no-helpers` logs its argv,
  working folder and PATH, prints a `model: gpt-x-test` header on stderr and writes the `-o` file; a fixture
  routing file whose `codex-reviewer` model is `gpt-x-test`; `COMMANDECK_SEAT=builder` unless the case says):
  "a call returns Codex's answer and the model that gave it" (first line `codex-ask: model gpt-x-test, `, then the
  stub's answer; one row with outcome `answered` and model `gpt-x-test`); "the call runs read-only outside the
  repository" (argv holds `-s read-only`, `--ephemeral`, `--skip-git-repo-check`, `-m gpt-x-test`; the working folder
  is not under the worktree or main; the real `codex` is reached through `codex-no-helpers`); "a plan-author pane may
  ask" (`COMMANDECK_SEAT=plan-author`: exit 0); "a plan-judge seat is refused" (`COMMANDECK_SEAT=plan-judge-fable`:
  exit 2, no stub call, no row); "a setup whose reviews run on Claude is refused" (`codexReviewerAgent=claude`: exit
  2); "a Codex failure fails loudly" (the stub exits 3 after `error: boom`: exit 1, stderr names `boom`, stdout empty,
  row `failed`); "an empty answer fails loudly" (exit 1, row `empty`); "an answer with no model header fails loudly"
  (the stub writes a non-empty answer, exits 0 and prints no `model:` line: exit 1, stderr names the missing `model:`
  header, stdout empty, row `no-model` with a null model, and no `unknown` anywhere in stdout, stderr or the row); "a
  long answer is cut and says so" (7000 bytes: 6000 printed and the cut line); "a call after a torn row is recorded on
  its own line"; then the two timed checks: "a timeout fails loudly" (`--timeout 1`, the stub `exec`s `sleep 30` and
  stops on TERM: exit 1 within 3 s, stderr `codex-ask: TIMEOUT: no answer within 1 s`, stdout empty, row `timeout`)
  and "a Codex that ignores TERM is killed after the grace" (`--timeout 1`, the stub `exec`s `python3 -c 'import
  signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'`: exit 1 within 5 s, stderr names
  `TIMEOUT` and the 2 s grace, stdout empty, row `killed`, and no stub process left, by a marker word in its argv and
  `pgrep -f`); last, "a real Codex refuses a write" (L7: a fixture repo, the question asks Codex to write a file there;
  the file is unchanged and exit is 0).
- `scripts/__tests__/worktreereview.test.sh`: "the review shows Codex helper calls and time" (a metrics file with two
  rows of the unit, one failed, and one of another unit: `Codex helper: 2 calls, <secs> s, 1 failed`); "a build with
  no Codex call says none".
- `scripts/__tests__/seat-plan-marker.test.sh`: "the helper line names the Codex helper" (the plan-author prompt holds
  the scripts folder's `codex-ask.sh`).
- `scripts/__tests__/worktree-setup.test.sh`: "a worker worktree allows the Codex helper" (the allow list holds
  `Bash(bash <scripts>/codex-ask.sh:*)`).

Break: scripts/__tests__/codex-ask.test.sh -- the call runs read-only outside the repository -- scripts/codex-ask.sh the -s read-only word (replaced by workspace-write)
Break: scripts/__tests__/codex-ask.test.sh -- a plan-judge seat is refused -- scripts/codex-ask.sh the is_helper_pane refusal
Break: scripts/__tests__/codex-ask.test.sh -- a timeout fails loudly -- scripts/codex-ask.sh the rc 124 branch (replaced by printing the empty answer)
Break: scripts/__tests__/codex-ask.test.sh -- a call returns Codex's answer and the model that gave it -- scripts/codex-ask.sh the metrics append
Break: scripts/__tests__/codex-ask.test.sh -- a Codex that ignores TERM is killed after the grace -- scripts/codex-ask.sh the `-k 2` of the timeout call (removed)
Break: scripts/__tests__/codex-ask.test.sh -- an answer with no model header fails loudly -- scripts/codex-ask.sh the no-model failure (replaced by recording `unknown` and exit 0)

### C9 -- #386 recorded, docs, release (~40 lines)

L1 is the whole of #386. `docs/review-loop.md` gains the closing-pass typecheck (C2) and the placeholder P1 (C5);
`docs/hooks.md` the tripwire's placeholder copy rule (C5) and the guard row (C7). Version and CHANGELOG below.

## Data design

- `<main>/.claude/metrics/unit-holds.jsonl` (new, C6): the one true copy of "unit X was parked from A to B". Writer:
  `unit-hold.sh` only, one `>>` append of one line under 4 KB, atomic on a local file system, so two writers both land
  and no lock is needed; the only read before writing is the last byte (a torn earlier append gets a fresh line).
  A failed append exits 1 and leaves no row; a half line a reader meets is skipped (`holds_for` skips non-JSON). Pairing
  is the reader's. No retries: the caller runs it again.
- `settled=<task>` lines in `$PP_SCRATCH/seat-<unit>-builder.txt` (existing marker, a second writer, C3): written only
  after `pp_task_close` succeeds, so a rerun after a later failure does not close a task twice; Orca's task state stays
  Orca's. Two closes at once (a merge and a sweep): `pp_task_close` on a closed task fails, is printed, and changes
  nothing.
- `.claude/commandeck.json` keys `typecheckCommand` (C2) and `screenPaths` (C4): setup is the one writer, as for
  `testCommand`; scripts and hooks only read. A re-run keeps them (`old`). Absent `typecheckCommand`: the gate is off;
  absent `screenPaths`: the default `web/src/`; `"screenPaths": []`: the screen and placeholder checks are off.
- `config/routing.json` `roles.builder.helpers` (C7): the one home of the helper models; the guard and the docs read it.
  A routing overlay (`COMMANDECK_ROUTING`) written before C7 has no `helpers` in its builder row (setup's
  `il_routing_merged` keeps an existing row as it is): the guard then reads the shipped map; only an overlay map that is
  present but not a non-empty object, or a file jq cannot read, leaves the call unchanged with the one `systemMessage`.
- `Placeholder: <file> | <complete source line> | <why>` lines (C5): written by main or the plan author in the plan
  (committed on main) or main's rulings file; read by the merge, the tripwire and plan-check. Each approves one added
  line equal to it after trimming. The Builder's own branch copy of the plan is never read for it.
- `always_disabled_lines` (C5 item 1; fix round 4, class jsx-context) stores nothing: it reads one line at a time
  and keeps only that line's text and its line number, inside one awk run over one text (the file at the branch tip,
  or the plan or batch). Fix round 4 drops rounds 2 and 3's context stack, expression-start flag and root stack: no
  state crosses a line, so no line's result depends on another's. Every merge, plan check and test reruns it from
  that text alone, so its one retry is the same for every caller and every input: run the merge (or the plan check)
  again on the new tip. Nothing is left to clear between runs.
- `<main>/.claude/metrics/codex-helper.jsonl` (new, C10): one row per Codex helper call. Writer: `codex-ask.sh`
  only, one `>>` append of one line under 4 KB, the same rules as `unit-holds.jsonl` (no lock, a fresh line after a
  torn one, a reader skips non-JSON); reader: `collect.py`. A call whose append fails still prints its answer and
  warns.
- Worktree permissions (C7 item 3a): a planning worktree's `settings.local.json` no longer denies `Agent`; the Claude
  judge and reviewer panes deny it through their routed `tools` list instead.
- `unit-holds.jsonl` and `codex-helper.jsonl` are project running state like the other ledgers: both in `IL_STATE`
  (`install-lib.sh`, hidden from git, reported by the doctor when tracked) and removed by `uninstall.sh --delete-data`.
  `unit-hold.sh` makes the missing `.claude/metrics` folder before its append (a fresh project has none), as
  `codex-ask.sh` already does.
- Lockfile reads (C11, #401), three pieces of state:
  - `.claude/commandeck.json` `lockfileDeny` (true | false; absent means on): writer `setup.sh` only (`--lockfile-deny`
    or the "Lockfile reads" question), kept on a re-run (`old .lockfileDeny`); reader `setup.sh`, which runs
    `il_lockfile_deny` on or off from it. Uninstall puts `commandeck.json` back as setup found it (`il_record own`).
  - `<main>/.claude/settings.json` `.permissions.deny` entries `Read(**/<lockfile name>)`, one per name in
    `IL_LOCKFILES` the checkout tracks (`git ls-files`): writer `il_lockfile_deny`, after setup's
    `il_record "$IL_PROJECT" merge "$PSET"` has noted the file's prior bytes; it only appends, never replaces the list,
    and never adds a rule already there (that rule stays the owner's). Reader: Claude Code's permission check. Removed
    by `il_lockfile_deny ... off` (`--lockfile-deny off`, and `uninstall.sh`), which takes out exactly the recorded rules.
  - Manifest `~/.commandeck/install/<project>.json` `.entries[<settings path>].denied`: the rules setup itself added,
    so off and uninstall can tell them from the owner's. Writer `il_lockfile_deny` only (`+ $n | unique` on add,
    `del(...)` on off); reader `il_lockfile_deny off`. `--plan` writes neither file (`il_write` previews, `il_set`
    returns at once).
  - Order and recovery: on add the record is written first, then settings. Cut off after the record: the rule is
    recorded but absent; a rerun adds it (it is still missing from the deny list) and records it again (`unique`), and
    off takes out a recorded rule that is absent with no effect. The reverse order would leave a rule in settings with
    no record, which every later run reads as the owner's and which off and uninstall then never remove. On off the
    settings write comes first, then the record is deleted: cut off between, a rerun of off subtracts nothing and
    deletes the record. The one recovery in each case: run setup (or uninstall) again. Accepted: a recorded rule whose
    settings write failed, later added by the owner by hand, is taken out by off.
- No stored data changes shape; no compatibility path.

Failure paths (every changed write and refusal):

| where | failure | result |
|---|---|---|
| `plan-check.sh` | plan or batch unreadable | exit 2, `REFUSED:` naming the file; writes nothing |
| `seat.sh` judge launch | plan-check refuses | exit 2 before the worktree, pane, task or record |
| `builder-launch.sh` arguments | missing or `--` value, unknown option, extra argument | exit 2 with the usage line, before `paths.sh` is sourced |
| `builder-add-work.sh` | no probe / all present / `git grep` fails | exit 2 / exit 4 / exit 1; nothing written or sent |
| `builder-codex-pass.sh` final | typecheck red | `die` before any reviewer; the rebase-pending file untouched |
| `merge-unit-local.sh` step 1 | evidence unreadable, screens missing, placeholder UI, a screen file's diff unreadable | `fail` before step 2, the branch untouched |
| `il_lockfile_deny` (setup) | manifest record fails / settings write fails after the record | `return 1`, settings untouched / the rule recorded but absent: a rerun adds it, off is a no-op for it |
| `unit-close.sh merged` (step 5) | no record, pane working, Orca refuses | the NOT-closed line; the merge's exit code and cleanup unchanged |
| `unit-close.sh drop` | merged, close refused, pane stuck, second pane listing unreadable or nonempty, remove fails | refuses before anything / stops before panes / keeps the worktree / keeps the worktree / exit 1 after the task is failed (a rerun removes) |
| `unit-close.sh --sweep` | list unreadable, one close refused | exit 1 naming the run; each refusal listed, the rest still close |
| `unit-hold.sh` | bad arguments / folder cannot be made or append fails | exit 2 usage / exit 1 naming the file, no row |
| `paths.sh` | non-bash shell | `return 1` before any variable is set |
| `agent-model-guard.sh` | routing unreadable, jq fails, a helpers map that is not a non-empty object (an overlay with none runs the shipped map) | call unchanged, one `systemMessage` line, exit 0 |
| `run-hook.sh` | no Bash 4 | one `systemMessage` line, exit 0, no hook ran |
| `codex-ask.sh` | not a helper pane / reviews on Claude / bad `--timeout` | exit 2 before any Codex call, no row |
| `codex-ask.sh` | timeout (TERM obeyed, or ignored and killed after the 2 s grace) | exit 1 within `<s>` + 2 s, one `TIMEOUT:` line on stderr, nothing on stdout, a `timeout` or `killed` row |
| `codex-ask.sh` | Codex error, empty answer, answer with no `model:` header | exit 1, one `FAILED:` line on stderr, nothing on stdout, a row with the outcome |
| `codex-ask.sh` | metrics append fails | the answer printed, a warning on stderr, exit code unchanged |

## Guards changed (each blocks more than before; what it blocked before and after)

| guard | blocked before | blocks after |
|---|---|---|
| `builder-launch.sh` arguments | an unknown option before the unit (as "bad unit name"); words after the batch ignored | an unknown option anywhere; a third positional; a value option with no value or a `--` value |
| plan checks | at Builder launch only | the same faults at every launch of a judge that certifies the plan; plus a `Mockup:` the batch lacks or a missing mockup file |
| `builder-add-work.sh` | a send after the first pass without `--small` | also a send with no probe (refused) and one whose probes are all on the branch (answered already done) |
| `builder-codex-pass.sh` final | a red rebase test run, a red full suite when on | also a red `typecheckCommand` |
| `merge-unit-local.sh` step 1 | nothing about screens or placeholders | a screen diff with no screenshot evidence or a named missing file; an added screen-code line holding placeholder copy or a literal-true `disabled` attribute inside a tag, unless a `Placeholder:` line names that complete line |
| `edit-content-tripwires.sh` (strict tier) | placeholder comments | also placeholder copy in screen code (the path taken against the file's own worktree root) whose complete line no `Placeholder:` line names |
| `codex-ask.sh` (new) | nothing (no Codex helper) | a call from a judge or reviewer seat; a call when the reviews run on Claude |
| worker tool denial | `Agent` in every worker worktree but a Builder's, so a plan author had no helpers and a Claude judge or reviewer in a Builder worktree had them | `Agent` in every unmarked worker worktree and in every Claude judge and reviewer pane, wherever it runs; a planning worktree allows it |
| `paths.sh` | nothing (a non-bash shell failed later, "no project here") | every non-bash shell, first |
| `unit-close.sh drop` (new) | nothing (no removal script) | dropping a merged unit; dropping while the Builder works |
| `agent-model-guard.sh` | rewrote a Builder's Explore whatever it named; never refuses | also rewrites general-purpose and debugger in a Builder pane, and all three in a plan-author pane and a fix round; a plan-judge or reviewer seat in a Builder worktree is no longer forced; still never refuses |

Unchanged: `--answer`-free sends that name probes, non-judge seats, judges with no `Plan:` line, narrowed passes,
non-screen merges, projects with `"screenPaths": []` or no `typecheckCommand`, bash sourcing of `paths.sh`.

## Prior art

GNU getopt argument permutation (options anywhere, unknown options refused) over POSIX Guideline 9, with a `--` word
refused as a value (getopt would take it, which is this issue's dry-run bug). Shift-left checks: mechanical checks run
before reviewers are requested (Danger, required status checks). Idempotent operations: check the state before acting
(`terraform plan`). Value-stream mapping separates process time from wait time. Lifecycle finalizers plus a reconciler
sweep (Kubernetes) for the task close. Visual review before merge (Chromatic, Percy), here as evidence presence only.
Feature-flag hygiene: unshipped UI stays out of the build rather than shipping disabled. Every cut ports the host's
reference implementation in commit `fea64e3e` where one exists, adapted to the plugin's files; no outside library.

## Decisions

1. **plan-check holds the plugin's own launch checks, not the host's caps.** The plugin's launcher has no file, line
   or cut cap (`rg -n 'Split override|files, cap' scripts` is empty, 2026-10-26), so the issue's "file count against
   the cap" has no plugin check to move; the test uses a check the plugin has (no size line). Adding caps is a new
   guard nobody ordered. Test: "a judge launch on a plan with no size line is refused"
2. **Byte-identical messages and order.** The batch checks run at the launcher's old place through `--batch-only`, so a
   batch missing Prior art still refuses before the Launch line is read. Test: the existing cases of
   `builder-launch-resume-launch-line.test.sh` and `builder-launch-resume-from-plan.test.sh`, kept
3. **Only a judge that certifies the plan runs plan-check** (a whole `Plan: .claude/plans/<unit>.md` line and the file
   present, the condition `seat.sh:395` already uses). A judge with no such line records no plan and binds nothing,
   so it is not held to the launcher's checks. Test: "a judge with no Plan: line is not checked"
4. **The judge's batch is looked for in the worktree, then main's briefs.** The plugin keeps a `--from-plan` batch in
   the worktree (`builder-launch.sh:72`) and main writes batches in its own briefs folder; with neither, only the
   plan's own checks run and the launch checks the rest. Test: "a judge launch on a Tests: plan is refused" (no batch)
5. **Arguments, GNU style, with `--small` kept.** The plugin still has `--small` (`builder-launch.sh:56`), so it is a
   flag here, unlike the host. Test: "dry-run in every position launches nothing", "an unknown option is refused naming
   it"
6. **A no-probe send exits 2, the plugin's refusal code** (`builder-add-work.sh:10`: 2 refused), not the host's 1.
   Test: "no probe is refused"
7. **The typecheck gate runs `typecheckCommand` whenever it is set, on `final` passes.** The plugin has no file-to-
   project map, so the host's "only when `.ts` changed" is left to the command. The simpler option, no gate at all,
   loses: a closing pass spent on a tree that does not compile recurs (the issue), and `testCommand` need not
   typecheck. Test: "a closing pass on a red typecheck is refused before any reviewer"
8. **The task id comes from the seat record only** (`task=` and `answer_task=`). Test: "another unit's task is
   untouched"
9. **The merge closes the task first thing in `cleanup_step`**, so the normal merge and `--cleanup` both close it while
   `pp_task_close` can still read the Builder's pane, and a refusal never changes the merge's exit code. Test: "a merge
   closes its Builder task completed", "a refused task close leaves the merge's exit code and cleanup"
10. **Unmerged removal is `unit-close.sh <unit> drop '<reason>'`, forced, and only after a second pane listing reads
    empty.** The unit is abandoned on purpose (the host's choice), but a forced removal under a pane that still
    writes loses real work, so the drop keeps `cleanup_step`'s fail-closed rule: a close that answered ok is proved
    by listing again. Test: "a dropped unit's task is failed and its worktree removed", "a merged unit cannot be
    dropped", "a drop keeps the worktree when a closed pane is still listed", "a drop keeps the worktree when the
    second pane listing cannot be read"
11. **The sweep is a mode main runs once after the merge**; the Builder runs its dry run on a stub only. Test: "the sweep
    dry run changes nothing"
12. **Screen code is the `screenPaths` setting, defaulting to the host's rule** (main's ruling, 2026-10-26: "Port
    exactly" meant the host's logic, not its hardcoded path). Unset: `.tsx`/`.css`/`.html` under `web/src/`, tests
    excluded; set: the same file rule under the set folders; `[]`: off. A project whose folders match nothing skips the
    check. Test: "with the default, a screen diff under web/src with no evidence is refused", "a set folder replaces
    the default", "with screenPaths empty a screen diff merges unchecked", "a test file under screen folders merges",
    "a session started in a subdirectory still screens the file". A path is matched relative to the edited file's own
    worktree root (`screen_rel`), never the session's working folder, which may be a subfolder or another checkout;
    the absolute path stays for reads.
13. **"Requested" is a `Placeholder: <file> | <complete source line> | <why>` line in the plan as committed on local
    main or in main's rulings file.** The complete line by equality, never a substring, so naming one control (or a
    bare `disabled={true}`) approves no other; one approval per added line, so a copied control needs its own line;
    every occurrence on a line is checked; local main's copy, so the Builder cannot approve its own placeholder by
    editing its branch's plan; a why, so the explained disabled control the issue names passes. The cost: a plan
    written before the code must quote the line as it will be formatted; a mismatch is refused at merge with the
    exact line printed, and main adds it to its rulings file. Test: "a disabled control the plan names merges", "an
    approved and an unapproved control in one file: only the unapproved one is refused", "an approved and an
    unapproved control on one line are refused", "a bare-substring approval approves nothing", "copy named only by a
    substring of its line is refused", "placeholder copy main's rulings name merges"
14. **The merge check covers placeholder copy as well as always-disabled controls.** The edit block runs in the strict
    tier only (L4), so without it copy would be caught only by a reviewer, which missed it twice. Test: "an unrequested
    always-disabled control is refused and listed"
15. **Only a literal-true `disabled` attribute on a control counts as always disabled** (inside an opening tag, with no
    value, `={true}` or a string literal); a `disabled={expr}` is behaviour, and a `disabled` outside a tag is a
    variable, a parameter or a word. Fix round 4: the tag test is a fixed pattern over one line (C5 item 1), so a tag
    split over lines is a stated miss (Accepted failure mode 10), and inside a tag a quoted value or a `{...}` value is
    read whole, so an arrow-function prop or a quoted `>` before the attribute does not hide it. Test: "a dynamic
    disabled prop merges", "a variable named disabled and a dynamic prop merge", "a disabled attribute on its own line
    inside a tag is a stated miss", "a disabled control after an arrow-function prop is refused", "a disabled control
    after a quoted > is refused"
16. **The brief check is a flag, not a refusal, and flags literal disabled controls as well as copy.** A plan may quote
    placeholder UI to plan its removal; the judge decides with the prompt line. Test: "a plan that describes
    placeholder UI as context is flagged and still launches", "a batch line naming a literal disabled control is
    flagged"
17. **Holds get their own file, not the decisions ledger** (a hold is not a question for the owner). Test: "a hold
    between two plan sessions is cut and listed"
18. **A hold never cuts a busy span** (a Codex run or a background job of any session). Test: "a Codex run inside a
    hold stays work", "a hold is cut around every background job, whichever session shows the wait"
19. **The guard enforces both helper models in a Builder pane, a plan-author pane and a fix round; elsewhere it fills
    only an unnamed model.** The pane is read from `COMMANDECK_SEAT` first and the worktree's `COMMANDECK_BUILDER`
    only when no seat is named, so a plan-judge or reviewer seat keeps a model it names on purpose (the owner: "reviewer
    and plan-judge seats are untouched"), wherever it runs. Test: "a Builder's general-purpose call naming opus runs as
    Sonnet", "a plan-author pane's general-purpose call naming opus runs as Sonnet and its Explore naming sonnet as
    Haiku", "a fix round in the Builder's pane enforces both models", "a plan-judge seat in a Builder worktree keeps
    its named model", "a named model outside these panes runs as named", "a call already on its configured model
    passes unchanged"
20. **`worktree-setup.sh` registers the guard in every worker worktree** (the measured cause, A4: plugin hooks are not
    active in the plugin's own worktrees), accepting a double run where `hooks.json` also loads (L6). Test: "a Builder
    worktree created the normal way runs Explore on Haiku and general-purpose on Sonnet", "a worker worktree registers
    the model guard too", "a rerun registers it once"
21. **#393's fix is the parenthesis, not a GNU-awk requirement.** One construct, one site; requiring gawk would add a
    setup install for every Mac. Test: "no awk print list in the shell scripts holds an unparenthesized comparison"
22. **`paths.sh` refuses a non-bash shell** (the host's fix, ported as the spec orders). The spec's "works when sourced
    from zsh" is read as the host read it: a zsh caller gets one clear line at once instead of the misleading "no
    project here"; making the other 1,500 lines of Bash 4 run under zsh is a redesign. Test: "sourced from a non-bash
    shell"
23. **#390 closes on a pin.** The plugin has no sibling reader; the issue's input through its one reader shows the age.
    Test: "a stale snapshot shows its age beside its rows"
24. **#386 ports nothing** (main's answer, L1). Test: none, no code changes
26. **The helper line is one constant, three readers, and the review flags over 300 lines with no helper** (the
    owner's numbers). The template is markdown and cannot read the constant, so a test holds it word for word.
    Test: "the Builder brief template carries the helper line word for word", "a build over 300 changed lines with no
    helper is flagged", "a build of 300 lines with no helper is not flagged"
25. **A guard or runner failure is a `systemMessage` with exit 0, never a block.** The runner's no-Bash-4 path runs
    before every hook, many registered with `onFailure: block`, so a non-zero exit there would block every guarded
    command; a message the person sees reports it without blocking. Test: "with no Bash 4 the runner's line is a
    message the person sees", "an unreadable routing file changes nothing and is reported"
27. **A planning worktree allows `Agent`; Claude judges and reviewers deny it in their own pane.** Plan authors,
    judges and reviewers share one worktree (`seat.sh:84`), so a worktree setting alone cannot allow the author and
    deny the judge; the routed `tools` list is per pane and already holds every Claude judge's and reviewer's denials.
    The simpler option, a `--planner` flag that allows `Agent` only on a plan-author launch, loses: the next judge
    launch's setup run would write the denial back over the author's pane. Test: "a planning worktree's settings allow
    helpers", "an unmarked worker worktree still denies helpers", "a plan-author seat's pane can start helpers", "a
    Claude plan judge in the same planning worktree cannot start helpers", "the headless Claude reviewer cannot start
    helpers"
28. **The Codex helper runs on the runner of the pass's sign-in probe, `codex exec`, not the review's companion and
    broker.** Same CLI, sign-in, wrapper (`codex-no-helpers`), hook retrust and read-only flag; a broker per question
    and the pass's session proof are for long persisted review threads, and `--ephemeral` keeps a helper call out of
    the review's Codex pass search (`collect.py:611` reads sessions by worktree). The issue's "untrusted" is met by
    never reading the repository's config: the working folder is outside it. Test: "the call runs read-only outside
    the repository", "a call returns Codex's answer and the model that gave it"
29. **The helper uses the review pass's Codex model and effort (`roles.codex-reviewer`), with no setting of its own,
    and the panes `is_helper_pane` names.** One model the owner already chose for Codex work; a judge or reviewer
    never calls it (the spec names Builders, planners and fixers). Test: "a plan-judge seat is refused", "a
    plan-author pane may ask", "a setup whose reviews run on Claude is refused"
30. **Bounds: 300 s by default (1-1800 by option), then TERM, then KILL after a 2 s grace; 6000 bytes of answer, a cut
    that says so.** A pane waits on the call, so it cannot hang: plain `timeout` sends TERM and waits, and a Codex that
    ignores TERM held the call 30 s past a 1 s deadline (A19); the grace's KILL cannot be caught. 2 s is short beside any
    deadline, and a stub that stops on TERM ended 0.06 s after it (A19); a real Codex slower than 2 s on TERM is
    killed, which costs nothing, since a timed-out answer is never used. A long answer would fill the
    pane's context. Test: "a timeout fails loudly", "a Codex that ignores TERM is killed after the grace", "a long
    answer is cut and says so"
31. **An answer whose model cannot be read is a failure, not `unknown`.** #399 asks that the call record which model
    answered; Codex prints it only in its stderr header (A18), so a missing header means the record cannot be made,
    and a success row with `unknown` would hide a changed Codex output. The answer is not printed, so the pane never
    acts on an answer of unknown origin; the pane asks again or works without it. Test: "an answer with no model header
    fails loudly"

## Accepted failure modes

1. A false "no visual change" row, or an unrelated image, passes: existence is checked, content is not; the merge log
   prints the reason. Test: none, a content check needs a baseline store this plugin lacks
2. A mockup named only in prose is not checked. Test: none, the `Mockup:` line is the contract (C1 item 3)
3. A probe that matches for an unrelated reason answers "already done" wrongly; main sends again with a sharper probe.
   Test: none, a probe's wording is main's judgment
4. A hold nobody records shows as unexplained idle, not a cut. Test: "a gap with no record is unexplained idle, not
   stage time"
5. A worktree removed outside `unit-close.sh` leaves its task open until main sweeps; a task whose record was lost is
   listed, not closed. Test: "no record closes nothing", "the sweep skips another repository's record and lists a task
   with no record"
6. A background job whose end the log never records keeps every later second out of a hold until the review's end.
   Test: "a hold is cut around every background job, whichever session shows the wait"
7. Placeholder copy worded outside the list passes the tripwire and the merge; the review's P1 is the catch. Test: "the
   review prompt names placeholder UI as P1"
8. A project with no `typecheckCommand` gets no typecheck before its closing pass. Test: "a closing pass with no
   typecheckCommand runs no typecheck and says so"
9. An owner's routing overlay that replaces a Claude judge's or reviewer's `tools` list without `Agent` lets that pane
   start helpers: the validator holds overlays to the write tools only (`paths.sh:826`), and refusing older overlays
   would fail every launch that reads them. Test: "the headless Claude reviewer cannot start helpers" (the shipped
   lists carry it)
10. `always_disabled_lines` is a fixed pattern over one line (fix round 4, class jsx-context; main's answers
   answer-1793068128-36463 and answer-1793068518-93805), not a TSX parser. Missed: a tag split over lines (a
   `disabled` on its own line, a value on a later line, a multiline `{...}` value, so changing only the value line of
   a multiline `disabled={...}` to `true` merges), a value with nested braces, type arguments on the tag
   (`<Select<O> disabled>`), an unquoted HTML value (`disabled=disabled`) and a comment inside `{true}`; the review's
   P1 (C5 item 5) is the catch. Falsely refused: a single-line control spelled in a string, template or comment of a
   screen file (`const s = "<Button disabled>";`), and a comment between `disabled` and its `=`; the recovery is a
   `Placeholder:` line naming that complete line (why: a source example) or moving the example out of screen code
   (tests and stories are not screen code); in a plan or batch it is a `FLAG:` line only, exit unchanged. No input
   on one line changes another line's result. Test: "a disabled attribute on its own line inside a tag is a stated
   miss", "changing only the value of a multiline disabled attribute to true is a stated miss", "scanner: every line
   is judged alone, whatever came before it"

## Assumptions (each settled, or a Builder check with the action per outcome)

- A1 [settled] #393's failing step. Run 2026-10-26 on the Mac: `builder-codex-pass-fresh-round.test.sh` with a folder
  whose `awk` links `/usr/bin/awk` (BSD `awk version 20200816`) first on PATH: 14 passed, 15 failed; the NO-GO pass
  exited 2 with `awk: syntax error at source line 4 ... n[c] >>> == <<< 1 ? "" : "s"`, the findings-so-far program at
  `scripts/builder-codex-pass.sh:1803-1806`. The same file on a copy of the tree with only that ternary parenthesized,
  same PATH: 29 passed, 0 failed. `rg -n --pcre2` over every `print`/`printf` argument list of `scripts`, `hooks`
  and `skills` shell files for an unparenthesized comparison followed by `?` found only `:1806`.
- A2 [settled] A gone pane reads idle: `bash -c '. scripts/codex-helpers.sh; pane_is_busy term_nonexistent_x'` returned
  1 (2026-10-26), so `pp_task_close` lets the sweep close a gone unit's task (the host's A6 holds here).
- A3 [settled] L3's counts, and both closeable tasks' units have a `mergeSha` row in the unit ledger
  (`ab603a45...`, `b63b0a4d...`), each on local main.
- A4 [settled] #397's cause. `~/.claude/hook-fire-log/<project>.2026-10-2[3-6].jsonl` for this repository: 48 Agent
  PreToolUse calls in Builder panes fired `builder-event-log.sh` and `builder-search-guard.sh` (registered by
  `worktree-setup.sh --builder`) and never `agent-model-guard.sh` (0 rows on 2026-10-24, -25, -26); the Claude profile's
  `plugins/installed_plugins.json` lists no commandeck plugin, so `hooks/hooks.json` never loaded there. A Builder that
  names `opus` on a general-purpose call keeps it today even where the guard loads (`agent-model-guard.sh:21-23`).
- A5 [settled] No sibling reader: `rg -n -i 'sibling|readSiblings' hooks/units.tsx hooks/units-sources.ts` is empty;
  `readSnapshot` (`units.tsx:65-75`) parses one file for `p.project` (2026-10-26).
- A6 [settled] L1's evidence, as stated there.
- A7 [settled] #395 reproduces: `cd /tmp && zsh -f -c '. "<checkout>/scripts/paths.sh"'` printed `no such file or
  directory: ./requirements.sh`, `./project-main.sh`, then `paths.sh: no project here`, rc 1 (2026-10-26). The PC has
  dash and no zsh (L2), so the test takes zsh, else dash.
- A8 [Builder check, before C2 step 2 and C4 step 2] `rg -n -- '--full-suite|--test-command|TAKES' scripts/__tests__`
  lists `setup.test.sh`, `plugin-option.test.sh`, `plugin.test.sh`, `install-lib.test.sh`, `requirements.test.sh`.
  Run them after adding the flags. Green: go on. Red on a flag list or question count: add the new flags or the
  question to the pinned list (the pin's purpose is that every flag is known), never drop the flag.
- A9 [settled] The pass fixture keeps main's config at `$REPO/.claude/commandeck.json` and has `cfg '<jq>'` to edit it
  (`fixtures/builder-codex-pass-setup.sh:107`, `:157`): C2's gate cases set `typecheckCommand` with it.
- A10 [Builder check, after every `templates/main-session.md` edit] The file is at its 200-line cap (`wc -l`, 2026-10-26;
  `plugin.test.sh` checks it). Join lines inside a bullet to stay at 200. Then run `hooks/__tests__/agent-startup-
  context.test.sh` and `scripts/__tests__/merge-rules.test.sh`. Green: go on. Red on a reworded rule: add its
  `MADE_FROM` line in `scripts/merge-rules.py` (as 0.51.0 did); red on a dropped first bullet: move the join, as
  0.51.0's change log says.
- A11 [Builder check, before C7 step 1] `rg -n 'has unknown field' scripts/__tests__ hooks/__tests__`: the file it
  names takes the helpers validation case; none: add the case to `worktree-setup.test.sh` beside C7's registration
  case. Run `worktree-setup.test.sh` after step 3: a check that pins the exact Builder hook list flips to include the
  guard.
- A12 [settled] `seat-run.test.sh:10` writes `the plan` as the judged plan and `:21`, `:51` send judges a `Plan:` line;
  plan-check refuses it (no size line). The Builder writes a passing fixture plan there (`## What can go wrong` with one
  line, `- Planned size: 1 files, 1 changed lines`); `:33`'s later `plan B` write happens after the launch, unchecked.
- A13 [settled] No merge test matches a `STEP 5 task` line: `rg -n 'STEP 5' scripts/__tests__` lists only `STEP 5
  cleanup` patterns (2026-10-26).
- A14 [Builder check, before C5 step 3] Read `hooks/__tests__/edit-content-tripwires.test.sh`'s payload helper. It
  builds an Edit payload on a path: the new cases put a fixture project (commandeck.json with `screenPaths`, a unit
  worktree whose brief names its plan, the plan committed on main) under the test's temp folder and edit inside it. If
  the helper cannot set the cwd the hook resolves the project from, add one parameter to it; existing cases unchanged.
- A15 [settled] The panes are told apart without a new marker: every seat pane runs `export COMMANDECK_SEAT=$ROLE`
  before its agent (`scripts/seat.sh:279`), the Builder is the seat `builder` (`builder-launch.sh:259`), plan authors
  are `plan-author*` (`seat.sh:92`, `:420`), and a fix round is the Builder's pane after `/clear`
  (`builder-fresh-round.sh:106`; `config/routing.json` `fixer` note: "Not a pane of its own"), so its process keeps
  the pane's env. The headless Claude reviewer cannot call a subagent (`--tools 'Read,Grep,Glob,Bash'`,
  `builder-codex-pass.sh:1596`), and the Codex reviewer is not Claude Code, so no reviewer call reaches the guard
  except from a seat whose `COMMANDECK_SEAT` names it (2026-10-26).
- A16 [Builder check, before C7 item 2b] `rg -n "flags" scripts/__tests__/worktreereview.test.sh` lists the cases that
  pin a run's flags. Run the file after item 2b. Green: go on. Red where a fixture now trips the helperless flag: the
  case pins its own flag, so add the new flag to its expected list (the flag is right: the fixture has no helper and
  over 300 lines), never raise the 300.
- A17 [settled] `--disallowedTools Agent` removes the subagent tool from a Claude pane. Run 2026-10-26, Claude Code
  2.1.311, in an empty folder: `claude -p --model haiku --output-format stream-json --verbose --disallowedTools <list>
  -- 'reply ok'`, the init event's tools filtered to Agent, Task, Write, Edit: with no list `["Task","Edit","Write"]`
  (the subagent tool reports as `Task`); with `Agent` `["Edit","Write"]`; with `Write,Edit,NotebookEdit,Agent` `[]`.
- A18 [settled] The Codex helper's runner, Codex CLI 0.164.0 on the Mac, 2026-10-26: `pp_route codex-reviewer` gives
  `gpt-6.1-sol medium`. `codex exec --json --ephemeral -s read-only -C <fixture repo> -m gpt-6.1-sol` asked to write
  `a.txt`: rc 0, the write refused, the file unchanged (L7); its `--json` events were `thread.started`,
  `turn.started`, `item.started`, `item.completed` (2), `turn.completed`, none with a model field. The same run
  without `--json` prints a header on stderr with `model: gpt-6.1-sol`, `sandbox: read-only`, `reasoning effort: low`
  lines, so the answering model is read from that header. `codex exec --ephemeral --skip-git-repo-check -s read-only
  -C <empty temp folder>` asked to `cat <fixture repo>/a.txt`: rc 0, answer `hi` (a read by absolute path from
  outside the repository works). `-o <file>` holds the last message.
- A19 [settled on the Mac; Builder check on the PC, before C10 item 1] The deadline-then-kill timing. Run 2026-10-26
  on the Mac, GNU coreutils `timeout` 9.12, a `codex` stub on PATH that `exec`s its sleeper (as `codex-no-helpers`
  `exec`s Codex): a stub that ignores TERM (`python3 -c 'import signal,time; signal.signal(signal.SIGTERM,
  signal.SIG_IGN); time.sleep(30)'`) under plain `timeout 1` was still running at 3 s and ended after 30 s; under
  `timeout -k 2 1`: rc 137 after 3.08 s; a stub that `exec`s `sleep 30` under `timeout -k 2 1`: rc 124 after 1.06 s.
  Builder check on the PC: run the same three commands there. Rc 124 / 137 and times within 1 s of the Mac's: go on.
  `timeout` lacks `-k` or reports other codes: stop and ask main (the tests run on the PC, so the timed checks'
  bounds would not hold), never widen the bounds.

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| a pane still listed after an ok close | `unit-close.sh u drop abandoned`, task settled; `terminal close` answers `{"ok":true}`; the second `terminal list` still names the pane | `KEPT` naming the handle, no `worktree remove`, exit 1 | a drop keeps the worktree when a closed pane is still listed |
| approved and unapproved controls on one line | `Placeholder: web/src/pages/X.tsx \| <Button disabled={true}>Export</Button> \| why`; added `<Button disabled={true}>Export</Button><Button disabled={true}>Delete</Button>` | refused, two entries for that line | an approved and an unapproved control on one line are refused |
| a `>` inside a JSX expression before the attribute | added `<Button onClick={() => save()} disabled={true}>Export</Button>` in `web/src/pages/X.tsx`, a screenshot row, no `Placeholder:` line | refused, one entry naming that line | a disabled control after an arrow-function prop is refused |
| a session started in a subfolder | strict hooks, default screen setting; hook run from `<wt>/web`; Edit `file_path=<wt>/web/src/X.tsx`, `new_string=<p>Coming soon</p>` | exit 2, the block naming the absolute path | a session started in a subdirectory still screens the file |
| a Codex helper that never answers and ignores TERM | `codex-ask.sh --timeout 1 'q'` in a Builder pane, the stub `codex` ignoring TERM and sleeping 30 s | exit 1 within 5 s, a `codex-ask: TIMEOUT:` line naming the 2 s grace on stderr, nothing on stdout, a `killed` row, no stub process left | a Codex that ignores TERM is killed after the grace |

Moved out of the table by its five-row cap, tests unchanged among the acceptance tests: a value option given a flag
(C1), a Codex run inside a hold (C6), a torn append before a release (C6), the sweep over merged, unmerged and live
units (C3), a disabled control the plan names (C5), a variable named `disabled` (C5, "a variable named disabled and a
dynamic prop merge"), a Codex that stops on TERM ("a timeout fails loudly") and an answer with no model header ("an
answer with no model header fails loudly", C10).

Added by fix round 1 (pass 1 findings marked "not in the plan list"; each test written red first):

| case | input or starting state | expected result | test name |
|---|---|---|---|
| a launched brief's plan heading | brief from `builder-launch.sh` naming the plan under `#### Plan`; the plan on main approves `$BTN` in `web/src/pages/X.tsx` | merges, no placeholder entry | a plan named under the launcher's #### Plan heading approves its control (`merge-unit-local-screens.test.sh`) |
| the hold CLI run as a command, first use | `scripts/unit-hold.sh u hold parked` run directly, its file under a `.claude/metrics` that does not exist | exit 0, the folder made, one `hold` row | the first hold in a fresh project makes the metrics folder, run as a command (`worktreereview.test.sh`) |
| a routing overlay from before C7 | `COMMANDECK_ROUTING` = shipped routing with `roles.builder.helpers` deleted; Builder pane general-purpose naming opus, Explore naming sonnet; unnamed Explore elsewhere | sonnet, haiku, haiku | an overlay with no helpers map runs the shipped helper models (`agent-model-guard.test.sh`) |
| source text that renders nothing | `const preview = "<Button disabled>…"`, a template, a `//` comment, a `{/* */}` JSX comment; `<p>Don't stop</p>` then a real control | fix round 4: each of the first four lines (a single-line control spelled in source text is refused, Accepted failure mode 10) and the real control's line | scanner: every line is judged alone, whatever came before it (`merge-unit-local-screens.test.sh`) |
| a multiline value change | main has `<Button` / `disabled={` / `busy` / `}`; the branch changes only `busy` to `true` | fix round 4: merges, no entry (a stated miss, Accepted failure mode 10; main accepted the flip, answer-1793068518-93805) | changing only the value of a multiline disabled attribute to true is a stated miss (`merge-unit-local-screens.test.sh`) |
| a background job across a session gap | sessions 0–60 and 600–660, a background job from 10 with no end; no hold | no unexplained idle, 660 s of stage time (a job ended at 100 leaves 100–600 unexplained) | a gap a background job covers is not unexplained idle (`worktreereview.test.sh`) |
| a setup run cut off between its writes | the manifest cannot be written during `il_lockfile_deny`; then a normal run; then off | settings untouched by the cut run; after the rerun and off only the owner's deny entry is left | a run cut off between its writes is finished by a rerun and taken out by off (`install-lib-setup.test.sh`) |
| a new ledger missing from IL_STATE | a script names `.claude/metrics/<x>.jsonl` that `install-lib.sh` does not list | the pin names it | every .claude/metrics ledger a script names is in IL_STATE (`plugin.test.sh`) |

Fix rounds 2 and 3 added three scanner rows here (every ordering for the context stack, a script in an `.html`
screen, a tag's comments); fix round 4 replaced that scanner, so their inputs are lines of the one case below.

Added by fix round 4 (pass 4's jsx-context finding, "not in the plan list"; the class's fourth return, so one case
holds every ordering found so far, in the order found; written red first):

| case | input or starting state | expected result | test name |
|---|---|---|---|
| every ordering that once misled the scanner, one text | in this order: pass 1's `"..."` string, template, `//` comment and `{/* */}` JSX comment each holding `<Button disabled>`, `<p>Don't stop</p>` then a real `<Button disabled>`, a `disabled` / newline / `={busy}` attribute; pass 2's `useState<string>("")` then a string holding `<Button disabled>`; round 2's `<T,>(x: T) => x`, `i <length` and `1 <<x`, a regular expression `/<Button disabled>/`; pass 3's `type F = <U>(u: U) => U` then a string `"</U>"`; pass 4's `type G = <U>(x: "</U>") => U` then `const view = <Button disabled />;`; round 2's `<script>` string then `<input disabled>`; `icon={<Button disabled />}` inside an attribute; round 3's four tag-comment lines; a multiline `<Button` / `disabled={` / `true` / `}` / `>` | exactly the lines whose own text holds a single-line constant-disabled tag (the source-text lines, the real controls, the regular expression, the `<script>` line, the attribute's control, `<A disabled /* c */ ={busy}>` and `<A /* note */ disabled>`), nothing on the multiline tag; and the whole text's output equals each line's output read alone | scanner: every line is judged alone, whatever came before it (`merge-unit-local-screens.test.sh`) |

## Claims to falsify

- Every existing `builder-launch.sh` refusal message, its exit code and their order are unchanged.
- A dry run never reaches `pp_sync_main`, a worktree or `seat.sh`, in any argument position, and no value option can
  take `--dry-run` as its value.
- `plan-check.sh` passes exactly the plans and batches the launcher passed before the move.
- A judge with no `Plan:` line, and every non-judge seat, launches exactly as before.
- `builder-add-work.sh` sends nothing when every probe is on the branch, and reads only committed work.
- A closing pass never starts a reviewer on a red `typecheckCommand`; a project without one is unchanged.
- `unit-close.sh` touches only tasks named in the unit's own Builder record (or, sweeping, records whose worktree is
  gone), and a landed merge's exit code never depends on it.
- A merge with no screen file changed, or in a project with `"screenPaths": []`, prints and refuses nothing new.
- A worker pane created the normal way runs the model guard even where the plugin's own hooks file is not loaded.
- A placeholder named on a `Placeholder:` line in the Builder's own branch copy of the plan, and nowhere on main, is
  still refused at merge.
- `unit-close.sh drop` never runs `worktree remove` unless a pane listing read after the closes is readable and empty.
- A `Placeholder:` line approves only an added line equal to its middle field after trimming; no substring of a line
  approves it.
- An added line with one approved and one unapproved control is refused.
- No `disabled` outside a single-line opening-tag pattern, and no `disabled={<expression>}`, is ever reported as
  placeholder UI.
- A `>` inside a `{...}` value without nested braces or a quoted attribute value never ends an opening tag, so a
  literal-true `disabled` after it on the same line is reported.
- No line's result depends on any other line: the whole text's output equals each line's output read alone.
- The tripwire screens an edited file by its path relative to its own worktree root, whatever folder the session
  started in.
- A plan-author pane has the `Agent` tool; a Claude plan-judge or reviewer pane does not, in a planning worktree or a
  Builder's.
- `codex-ask.sh` never runs Codex with a sandbox other than `read-only`, or from a folder inside the repository.
- `codex-ask.sh` never exits 0 without printing a non-empty answer and a model read from Codex's `model:` header; it
  never prints or records `unknown` as a model.
- `codex-ask.sh` returns within its timeout plus 2 s, even when Codex ignores TERM.
- A review with no holds and no 120 s gap with no session renders the same figures as before.
- A hold never cuts a second an active Codex run or a background job of any session covers.
- No environment variable sets a subagent model; a plan-judge or reviewer seat's named model is never rewritten, in any worktree.
- `paths.sh` sourced from bash behaves as before.
- After the fix, no awk program in the NO-GO path prints an error under BSD awk.

## Not ordered (found, not planned)

- `scripts/codex-helpers.sh:31` also finds `paths.sh` with `BASH_SOURCE`; sourced from zsh it fails before `paths.sh`
  can refuse. The issue names `paths.sh` only.
- The host's file, line and cut caps (Decision 1) and its `ship-unit.sh` twin (the plugin has no ship script).
- The edit-time placeholder block in the default tier (L4): a tier change for one rule is a hook-tier decision.

## Version and CHANGELOG

Version: the next free minor at merge time (0.52.0 if nothing lands first; `bash ci/version-check.sh` decides), in
`.claude-plugin/plugin.json`. One entry, in the release-note style (topic sections named for what a user sees, plain
sentences, no file names, paths, issue numbers or hashes). Draft:

```
## 0.52.0 -- <merge date>

### Launching builds

- Launch options now work in any position, before, between or after the unit name and the batch. An option the launcher does not know, an extra word, or an option missing its value is refused with the usage line, so a dry run can never turn into a real launch.
- A plan is checked by the same rules as a launch before any plan judge reads it, so no judging round is spent on a missing section or label.
- A plan names each mockup on its own line, and a launch refuses a plan whose mockup the batch does not carry.

### Builders

- Work added to a running build names a check for each item; work the branch already has is answered "already done" and not sent.
- A closing review pass waits for a green typecheck when the project sets one up.
- Helper agents run on the models set next to the Builder role: search helpers on Haiku, other helpers on Sonnet, enforced in build, planning and fix-round panes. Builders, planners and fix rounds are told to hand work to them, and the build review shows helper spend by model and flags a large build that used none.
- Builders are told to build only what the plan asks for, never a disabled or "coming soon" stand-in.
- Builders, planners and fix rounds can ask Codex a question, read-only, for a search or a second opinion. Each call has a time limit and an answer limit, names the model that answered, and says so plainly when it fails; the build review shows the calls and their time.
- Planners can now start helper agents. Plan judges and reviewers still cannot.

### Merging

- A build that changes screen code merges only with a side-by-side list, a screenshot that exists, or a stated reason that nothing visible changed. Setup asks which folders hold screen code.
- A merge refuses switched-off controls and "coming soon" copy that no plan or ruling asked for, and lists each one. The review treats them as serious findings.
- A merge closes the build's task, a build removed unmerged closes it as failed, and a sweep closes the ones left open before.

### Build review

- Time a build was parked on purpose is cut from the review, and gaps with nothing running are shown apart instead of counting as work.

### Fixes

- A failed review pass no longer ends with an error on a Mac's built-in awk.
- The shared script file now says so at once when it is loaded from a shell other than bash.
```

## Merge commit message

```
feat(plugin-open-2026-10-26b): every open plugin issue: launch and plan checks, add-work probes, screen and placeholder checks, task close, holds, helper models, a read-only Codex helper

Closes #384
Closes #385
Closes #387
Closes #390
Closes #392
Closes #393
Closes #394
Closes #395
Closes #396
Closes #397
Closes #398
Closes #399
Refs #386
```

An issue the progress notes leave `partial` moves from `Closes` to `Refs`. After the merge main leaves a one-line
comment on each closed issue naming what was built, and on #386 that the plugin has no Stop typecheck or tier-1 hook
to port into (L1); then main runs C3's sweep.

## Progress notes (the Builder keeps one line per issue in the evidence file's Issue status table)

```
#384: built | partial -- <what is left>
#385: built | partial -- <what is left>
#387: built | partial -- <what is left>
#390: built | partial -- <what is left>
#392: built | partial -- <what is left>
#393: built | partial -- <what is left>
#394: built | partial -- <what is left>
#395: built | partial -- <what is left>
#396: built | partial -- <what is left>
#397: built | partial -- <what is left>
#398: built | partial -- <what is left>
#399: built | partial -- <what is left>
#386: recorded (stated limit; stays open)
```

## Files edited

Code (20): `hooks/lib/run-hook.sh`, `scripts/plan-check.sh` (new), `scripts/builder-launch.sh`, `scripts/seat.sh`, `scripts/builder-add-work.sh`,
`scripts/builder-codex-pass.sh`, `scripts/merge-unit-local.sh`, `scripts/unit-close.sh` (new), `scripts/unit-hold.sh`
(new), `scripts/paths.sh`, `scripts/setup.sh`, `scripts/worktree-setup.sh`, `hooks/lib/screen-code.sh` (new),
`hooks/edit-content-tripwires.sh`, `hooks/agent-model-guard.sh`, `skills/worktreereview/scripts/collect.py`,
`skills/worktreereview/scripts/render.py`, `config/routing.json`, `scripts/codex-ask.sh` (new),
`hooks/lib/helper-pane.sh` (new).
Templates, docs and release (12): `templates/_builder-brief-template.md`, `templates/main-session.md`,
`templates/_batch-brief-template.md`, `skills/setup/SKILL.md`, `skills/worktreereview/SKILL.md`,
`docs/configuration.md`, `docs/setup-questions.md`, `docs/hooks.md`, `docs/review-loop.md`, `README.md`,
`CHANGELOG.md`; `.claude-plugin/plugin.json`.
Tests (19): `scripts/__tests__/plugin.test.sh`, `hooks/__tests__/run-hook.test.sh`, `scripts/__tests__/seat-plan-marker.test.sh`, `scripts/__tests__/builder-launch-resume-launch-line.test.sh`, `seat-launch.test.sh`, `seat-run.test.sh`,
`builder-add-work.test.sh`, `builder-codex-pass-rebase.test.sh`, `builder-codex-pass.test.sh`,
`builder-codex-pass-fresh-round.test.sh`, `merge-unit-local-screens.test.sh` (new), `unit-close.test.sh` (new),
`worktreereview.test.sh`, `project-main.test.sh`, `worktree-setup.test.sh`; `hooks/__tests__/agent-model-guard.test.sh`,
`hooks/__tests__/edit-content-tripwires.test.sh`; `hooks/units-sources.test.tsx`; `scripts/__tests__/codex-ask.test.sh` (new).
Contingent (A8, A10): a setup pin test, `scripts/merge-rules.py` and its test.

## 5. Build order and size (changed lines, code + tests + docs, estimates)

| Cut | Lines |
|---|---|
| C1 #394 #384 #392 launch | 262 |
| C2 #385 | 141 |
| C3 #396 | 296 |
| C4 #392 merge | 199 |
| C5 #398 | 278 |
| C6 #387 | 209 |
| C7 #397 | 209 |
| C8 #393 #395 #390 | 53 |
| C10 #399 | 334 |
| C9 #386, docs, release | 38 |
| Total | about 2019 |

Order: C1 first (plan-check, which C5 extends); C2; C3 (the merge's step 5) before C4 and C5 (step 1, same file, the
new test file C3 starts); C4 before C5 (C5 reads `is_screen`); C6, C7, C8 independent; C10 after C6 and C7 (it reads
C7's `is_helper_pane` and helper line and extends C7's review fact, beside C6's `holds_for`); C9 last (its CHANGELOG
entry holds every cut).

## Done when

- Every cut's named acceptance tests are green.
- `bash scripts/run-shell-tests.sh --changed main` green.
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- A closing (final) pass ends `VERDICT: GO` with no finding named.

## Question for the owner

None. Main answered the scope of #397 and the three port gaps (#386, #385's typecheck, #392's screen code), 2026-10-26; main added #399 to the unit, 2026-10-26.

## Plan change log

- 2026-10-26: first version, ten issues from the spec's list.
- 2026-10-26: #397 added (the owner's addition, main's answer: native build); C7, Decisions 19-20, A4, L6.
- 2026-10-26: main's answers on the port gaps: #386 a stated limit (L1, Decision 24); #385's typecheck is
  `typecheckCommand` with the no-gate option named and rejected (C2, Decision 7); #392's screen code is the
  `screenPaths` setting with the host's rule (C4, Decision 12).
- 2026-10-26: #398 added (the owner's addition in the spec's section 4): C5, Decisions 13-16, L4, accepted failure mode
  7, What can go wrong row 5; planned size 44 files, 1400 lines.
- 2026-10-26: main's ruling on #392: `screenPaths` unset means the host's `web/src/` rule, `[]` turns it off; Decision 12
  and C4's tests now cover a set folder and the default.
- 2026-10-26: #397's issue text rewritten: the guard is registered in every worker worktree, not only a Builder's
  (C7 item 3, Decision 20); a guard or runner failure is a message the person sees (C7 item 4, Decision 25); the
  issue's own test (a Builder worktree created the normal way) is C7's first worktree case; a pin keeps helper models
  in the review. Planned size 46 files, 1440 lines.
- 2026-10-26: #397 extended by the owner (spec section 3): plan-author panes and fix rounds enforce the helper models
  too, read from the existing `COMMANDECK_SEAT` marker before the worktree's Builder flag, so plan-judge and reviewer
  seats keep their named models (C7 item 2, Decision 19, A15); one standing helper line goes into the plan-author
  prompt, the fix-round hand-off and the Builder brief template (C7 item 2a, Decision 26); the build review prints
  helper count and spend by model and flags a build over 300 changed lines with no helper (C7 item 2b, A16). Planned
  size 47 files, 1510 lines.
- 2026-10-26: the plan judge's NO-GO answered (main's answers above); the next judge rechecks only these:
- F1: C3 item 1's drop lists the panes again after the closes; an unreadable or nonempty second listing keeps the
  worktree (Decision 10, two unit-close cases and Break lines, failure paths row, What can go wrong row, a claim).
- F2: C7 item 3a: a planning worktree (the `commandeck-plan-of` mark) drops the `Agent` denial; Claude judge and
  reviewer panes deny `Agent` through their routed `tools` list, since they share the worktree (Decision 27, A17,
  accepted failure mode 9, planner and reviewer permission cases, two Break lines, guards row; `plugin.test.sh` and
  `builder-codex-pass.test.sh:168` flip).
- F3: C5 item 2: a `Placeholder:` line names the complete added source line, matched by equality, one approval per
  line, every occurrence checked (Decision 13, same-file, same-line and bare-substring cases, two Break lines, What
  can go wrong row, claims).
- F4: C5 item 1: `always_disabled_lines` matches only a literal-true `disabled` attribute inside an opening tag
  (Decision 15, the declaration-plus-dynamic-prop and multi-line-tag cases, a Break line, What can go wrong row, a
  claim).
- F5: C4 item 1: `screen_rel` takes the edited file's path against its own worktree root; the tripwire keeps the
  absolute path for reads (Decision 12, absolute-path and subfolder-session cases, a Break line, What can go wrong row,
  a claim).
- F6: C5 item 7: the brief check also flags literal always-disabled controls (Decision 16, the judge's batch line as a
  case, a Break line). Planned size 48 files, 1655 lines; the What can go wrong table keeps five rows, the four it
  moved out listed under it with their tests unchanged.
- 2026-10-26: #399 added (main's message: the owner added it to this unit): C10, a read-only Codex helper
  (`codex-ask.sh` on the pass probe's `codex exec` runner, read-only, run from outside the repository, the reviewer's
  model, 300 s and 6000-byte bounds, loud failures, a metrics row per call); `is_helper_pane` moved into
  `hooks/lib/helper-pane.sh` so the guard and the helper share it (C7 item 2); the helper line names it (C7 item 2a);
  the review shows its calls and time; Decisions 28-30, L7, A18, What can go wrong row (the timeout; the torn-append
  row moved under the table), data design, failure paths, guards, claims, CHANGELOG, `Closes #399`. Planned size 51
  files, 1955 lines.
- 2026-10-26: the round-2 plan judge's NO-GO answered (main's round-2 answers above); the next judge rechecks only these:
- F4 r2: C5 item 1: `always_disabled_lines` ends an opening tag only at a `>` outside every quoted value and balanced `{...}` expression (Decision 15, the judge's arrow-function case and a quoted-`>` case, a Break line, What can go wrong row 3, a claim).
- F7: C10 item 1: `timeout -k 2`, TERM at the deadline and KILL after a 2 s grace, with its own `TIMEOUT:` lines for rc 124 and for rc 137 past the deadline (Decision 30, A19 measured on the Mac with a Builder check on the PC, a TERM-ignoring stub case within 5 s, a Break line, Timed checks line, failure paths row, What can go wrong row 5, a claim).
- F8: the complete-line equality Break line now runs on "a bare-substring approval approves nothing", which goes red under substring matching; the separate-lines case stays an acceptance test without a Break line (C5 Break lines).
- F9: C10 item 1: an answer with no `model:` header is exit 1 naming the missing header, row `no-model` with a null model, never `unknown` (Decision 31, a case and a Break line, failure paths row, the claim at Claims to falsify fixed). Planned size 51 files, 2019 lines.
- 2026-10-26 (fix round 2, design-only pass 3): class jsx-context came back in pass 2 (`useState<string>("")` put
  the scanner in JSX text). C5 item 1's scanner is redesigned around one stack of TSX's own contexts, TSX's
  expression-start rule for `<` and `/`, and an element proof for an opening tag; attribute expressions are scanned,
  not skipped; `--markup` skips `<script>` and `<style>` text. Data design bullet (the scanner stores nothing), two
  What can go wrong rows. No decision, limit or failure path changes.
- 2026-10-26 (fix round 3, design-only pass 4): class jsx-context came back in pass 3 (round 2's element proof
  searched the raw text for a closing tag, so a `"</U>"` string proved `type F = <U>(u: U) => U` an element). C5
  item 1's element proof is now a speculative element read in context: a root saved at its `<`, proven only when
  the scanner itself reaches its closer through well-formed TSX, otherwise rewound to that `<` as an operator.
  After a whole element an expression can start. A tag's comments and a `disabled` value are read in the tag's
  context (the round's sweep). Data design bullet (the root stack replaces the closer list), the all-orderings row
  gains pass 3's ordering, the .html row's input is fixed, one row added, accepted failure mode 10. No decision,
  limit or failure path changes.
- 2026-10-26 (fix round 4, design-only pass 5): class jsx-context came back in pass 4 (the accepted
  `<U>(x: "</U>")` gap can hide a real control on the next line). Under main's addendum (answer-1793068128-36463)
  parser rounds end: C5 item 1's scanner is replaced by a fixed pattern over one line, no state across lines, no
  flags (`--markup` and `--spans` go); main approved it with no per-line exclusion (answer-1793068518-93805).
  Accepted failure mode 10 is rewritten to its misses and false refusals. Two acceptance tests flip to the stated
  miss, as main accepted: "a disabled attribute on its own line inside a tag is refused" becomes "... is a stated
  miss", and "changing only the value of a multiline disabled attribute to true is refused" becomes "... is a stated
  miss". Decision 15, the Data design bullet, two claims, two Break line sites, the tripwire's reason in C5 item 3
  and the What can go wrong rows follow; rounds 2 and 3's three scanner rows become lines of one new case. No
  limit or failure path changes. After the design GO (pass 5), the code's break run showed the "variable named
  disabled" Break line's site is the value rule, not the tag pattern (removing the tag pattern cannot make
  `const disabled = busy;` literal-true); its site is corrected.

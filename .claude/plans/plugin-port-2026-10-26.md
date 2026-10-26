# Plan: plugin-port-2026-10-26: the drifted rule sections and the twins of the host's tooling fixes, one unit

Owner's words: the owner, 2026-10-26: "One plugin unit now" -- "New unit: port every drifted section plus the open twins of today's merged tooling fixes (#376-#390) in one plugin build." ONE unit, no split, whatever the size caps say.

Added by the owner's order, 2026-10-26 (spec section 4): "Add the plugin fix to current plugin build." #391, built
natively (its host twin is being built in parallel; there is no host commit to port).

Closes: #376, #377, #378, #379, #380, #381, #382, #383, #391
Refs (stated limits, recorded only, the issues stay open): #388, #389

- Planned size: 38 files, 890 changed lines

Tier: Standard. LOCAL merge only. Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no
test-timeout raises. No red or mutation proofs except the break runs this plan's `Break:` lines name: each is run red
before pass 1 and recorded in the evidence file as `Mutation-verified: <test file> -- <check label>: RED, <how>`
(beside the `## Break runs` line `break_gate` reads, Decision 10). One unit, no split.

Source of every port: the host's local main, commit `b4f8dccf` (`feat(tooling-open-40-2026-10-26)`); its own plan
names the twins (host issue 3198 = #376, 3196 = #377, 3195 = #378, 3194 = #379, 3197 = #380, 3162 = #381,
3011 = #382, 3193 = #383). Host hunks below are cited as `host <file> @@ -<line>` from `git show b4f8dccf`.
Rule drift: the 35 lines of the host's drift report of 2026-10-26, numbered R01-R35 in report order (section 3).

Timed checks: `scripts/__tests__/builder-codex-pass-fresh-round.test.sh` (`timeout 30` at :98),
`scripts/__tests__/seat-launch.test.sh` (`COMMANDECK_SEAT_SETTLE_SECONDS=0` launches at :24, :38, :60),
`scripts/__tests__/seat-plan-marker.test.sh` (`--timeout-s 20` at :83). The heavy cases this unit adds to them, a whole
NO-GO pass (C7, fresh-round file) and a Builder launch over a dead record (C7, seat-launch file), go after the last
timed check of their file. The seat-plan-marker change (C9) only flips a text check and adds no case.
`scripts/__tests__/merge-unit-local-cleanup.test.sh` runs under a file cap (`# timeout: 240`, :3) and took 117 s whole
(23 checks green, run 2026-10-26); C12 adds one merge to it (about 10 s), last in the file. The other touched test
files have no time-bound check (`grep -n 'timeout [0-9]\|timeout --\|^# timeout'`, 2026-10-26).

## Main answers

(binding; main's answers to the plan judge's four findings, 2026-10-26)

1. Copy cleanup: `drop_copy` never falls back to a raw `rm -rf`. A copy git refuses to remove (a locked worktree) is kept and named in the pass output; an unregistered leftover folder goes through `pp_rm_rf`. `scripts/builder-codex-pass.sh` stays off the raw-removal list of `scripts/__tests__/project-main.test.sh:90`. Test: "closing_copy_locked_kept: a registered, locked closing copy holding an uncommitted tracked change survives the pass with its change intact" (C3).
2. Break proofs: the owner's newer order is red proofs for the plan's `Break:` lines only. Every `Break:` line and Decision 10 stay; the Tier line says no red or mutation proofs except those break runs, each recorded as `Mutation-verified: <test file> -- <check label>: RED, <how>` before pass 1.
3. Claude closing-review cost: the Claude branch of `scripts/unit-cost.sh` (`:22-24`) also reads the copy's Claude project folder, and the transcript selector of `scripts/dashboard_limit.py` (`:1359`) also takes the copy's folder, so the copy's transcript reaches the `belongs` check. Test: "claude_closing_copy_cost_counted: one Claude closing-review request with cwd in the copy and none in the worktree is counted for the unit by unit-cost.sh and by the dashboard stages" (C3).
4. Every step this plan adds to the build, merge or review flow carries a `Catches:` line (`templates/_batch-brief-template.md:16-17`): C1, C2, C3, C4, C5, C8 and C9 (the prove step, the What can go wrong rule, the judge's checks, the halfway note, the sibling dry run).

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

- L1 (#388). The new-package guard misses an install inside a `case` pattern inside a double-quoted command
  substitution: `echo "$(case x in x) npm install lodash;; esac)"` fed to `hooks/dependency-addition-guard.sh` as a Bash
  payload returns 0; the same line unquoted returns 2 and a bare `npm install lodash` returns 2 (run 2026-10-26 with
  `jq -nc --arg c "$C" '{tool_name:"Bash",tool_input:{command:$c},session_id:"s",cwd:"/tmp"}' | bash hooks/dependency-addition-guard.sh`).
  The parser is not extended to read `case` syntax; the guard is a tripwire, not a boundary (its header, :27-32).
  Recorded in the hook header and `docs/hooks.md` (C10). Issue stays open.
- L2 (#389). The plugin's forced-remove exception (a temporary worktree this session added, `hooks/git-safety.sh:176-249`)
  reads no worktree status at all: `rg -n 'status --porcelain|ignore-submodules|ls-files -v' hooks/git-safety.sh`
  prints nothing (2026-10-26). So the issue's case (an assume-unchanged or skip-worktree file passing a clean check)
  has no clean check to pass here: a forced remove of such a worktree deletes whatever it holds, by the exception's
  design. The one-line `git ls-files -v` check the issue names is not ordered. Recorded in the hook header and
  `docs/hooks.md` (C10). Issue stays open.
- L3. The fresh closing reviewer's copy (C3) costs one checkout of the pass commit per closing pass: on this repository
  456 tracked files, 7972 KB (`git ls-files -z | xargs -0 du -ck | tail -1`), and `git worktree add -q --detach` took
  0.103 s (timed with `perl -MTime::HiRes`, 2026-10-26). The copy lives only while that pass runs. Its speed and disk
  use are not otherwise judged.
- L4. A closing copy left by a pass killed with SIGKILL (no EXIT trap runs) stays until the next fresh closing pass of
  that worktree removes it first (host behaviour, kept). Its git record is pruned at that removal.
- L5. Drift lines marked "not ported" in section 3 name host-only things (the host's machines, memory boxes, test
  lanes, deploy targets, ids, a host skill or script the plugin does not ship). A finding asking for one is out of scope.

## 1. Item map (what exists, what the host built, where it lands, the test)

| Issue | Host hunks ported (`b4f8dccf`) | Plugin today (file:line) | Lands at | Cut |
|---|---|---|---|---|
| #376 | host `.claude/scripts/builder-codex-pass.sh` @@ -208 (exit 3 prints when it began), @@ -442 (`earlier_passes` writes a `cut` row), @@ -464 (`review_stop_id`: a round short of its declared reviewers, or cut, holds as a P1), @@ -583 and @@ -664 (`--verify` skips `cut` rows in the chain, refuses a `cut` row after the closing pass), @@ -777 (the launch's earlier list skips `cut`); test `partial_round_keeps_p1_open` | A round with a row per answering reviewer already clears nothing when short (`scripts/builder-codex-pass.sh:430-441`, run below in Assumptions A1). Missing: a wholly cut-off round has no row at all (`:609-617` skips an rc 3 session), a short round does not itself hold, and a reply with no verdict (`said none`, `:350-355`) counts as a verdict | `scripts/builder-codex-pass.sh:297`, `:346`, `:406-445`, `:609-617`, `:711-715`, `:765-769`, `:970` | C1 |
| #377 | host `builder-codex-pass.sh` @@ -794 (`cap_gate_reason`, the plan-only test, the refusal), host `_builder-brief-template.md` @@ -217 line, host `orchestration.md` review-loop sentence; test `cap_stop_refuses_later_pass` | At the cap a `review` runs as `final` (`:1012-1016`); the merge takes a cap stop (`:671-678`). Nothing refuses a pass after a cap stop or a plan-only pass past the cap | after the REVIEW STOP gate, `scripts/builder-codex-pass.sh:984`; `templates/_builder-brief-template.md:200-204`; `docs/review-loop.md` | C2 |
| #378 | host `.claude/scripts/unit_folders.py` (new); `builder-codex-pass.sh` @@ -160 and @@ -208 (`session_proof` uses `belongs`), @@ -386 and @@ -418 (`pass_threads`), @@ -1212, @@ -1220, @@ -1238, @@ -1251 (the copy, its removal, the reviewers' `--cwd`, the session search); `dashboard_limit.py` @@ -51, @@ -1270, @@ -1471; `unit-cost.sh` @@ -111; test file `unit-folders.test.sh`; `orchestration.md` review-loop line | The closing reviewer runs in the worktree, kept from the round files by a prompt line only (`FRESH_HEAD`, `:194`; reviewers launched with `--cwd "$WT"`, `:1480`, `:1489`; Claude reviewer `cd "$WT"`, `:1460`) | new `scripts/unit_folders.py`; `scripts/builder-codex-pass.sh:304`, `:509`, `:522`, `:550`, `:570`, `:1396-1406`, `:1422-1461`, `:1480`, `:1489`, `:1503`; `scripts/unit-cost.sh:108-113`; `scripts/dashboard_limit.py:1252-1253`, `:1364-1365`; `scripts/dashboard.sh:957` | C3 |
| #379 | host `builder-codex-pass.sh` @@ -508 (`fix_groups`), @@ -1419 (`## Parallel fix groups` in the hand-off); host `_builder-brief-template.md` @@ -236 line | One fix brief, findings by class (`:1666-1689`); the Agent worktree-isolation rule already exists for helpers (`templates/_builder-brief-template.md:68-72`) | new function beside `open_findings` (`:637`); hand-off after `:1689`; template after `:246` | C4 |
| #380 | host `.claude/scripts/main-watch.sh` @@ -754 (`stop_next` takes the round, reads only a recognised answer naming it), @@ -778 and @@ -802 (`report_wake`: the superseded arm, the first-pass GO arm asks the stop check, the newest round read again before the stamp); fake verifier names the newest round; tests in `main-watch-auto-merge.test.sh` | `report_wake` stamps every round from its file text alone (`scripts/main-watch.sh:921-945`): no stop check (the plugin has no `stop_next`), an older round gets its own next step, nothing reads the newest round again | `scripts/main-watch.sh` new `stop_next` before `:918`, `report_wake` `:921-945`; `scripts/__tests__/fixtures/main-watch-merge-setup.sh:7-11` | C5 |
| #381 | host `.claude/hooks/resume-context.sh` @@ -123 (GONE lines from the checkpoint's named runs, one "not checked" line when the lookup fails, budget subtracts them), @@ -146 (payload); test cases in `resume-context.test.sh` | The detach half is built: a seat run main starts goes on under `setsid`/`nohup` (`scripts/seat.sh:171-180`, which cites host issue 3162). The resume block names no run that is gone (`hooks/resume-context.sh:124-153`) | `hooks/resume-context.sh` before `:127` and in `:153` | C6 |
| #382 | host `.claude/main-session.md` @@ -57 (the relaunch route in Do not -> instead); test `seat-launch-resume.test.sh` @@ -157 ("a builder launch over a record whose pane is gone writes the new pane's handle", status says `pane=gone`) | `seat.sh launch builder` refuses only a launch still running (`scripts/seat.sh:232-235`), so it already relaunches over a dead record; `seat.sh status` prints no pane state (`:129`, `:200-203`); no rule names the route | `templates/main-session.md:5-10`; `scripts/seat.sh:129` | C7 |
| #383 | host `.claude/briefs/_builder-brief-template.md` @@ -42 (the `## Issue status` table bullet); host `dashboard.test.sh` cut-style evidence fixture | `builder_progress` already counts an `Issue | Status` table's `built` rows (`scripts/dashboard.sh:221-245`); the template asks for a `## #<issue>` heading per item instead (`templates/_builder-brief-template.md:89-91`) | `templates/_builder-brief-template.md:89-91` | C8 |
| #391 | none: native build (no host commit) | The class-sites files (`<unit>-r<N>-class-sites.txt` and `.md`, written on every NO-GO, `scripts/builder-codex-pass.sh:1616-1617`) stay uncommitted in `.claude/briefs/` like every other review record, and the merge lets those through (step 1 `:210`, cleanup `:160` of `scripts/merge-unit-local.sh`): the worktree is removed (Assumption A11). The Sites refusal names `-class-sites.md` (`:1120`) where it reads `-class-sites.txt` (`:1117`) | `scripts/builder-codex-pass.sh:1120`; tests | C12 |
| drift | the 35 lines, section 3 | section 3 | section 3 | C9 |
| #388, #389 | none (stated limits) | L1, L2 | hook headers, `docs/hooks.md` | C10 |

## 2. Cuts (build order)

Each cut: what it changes, Produces / Consumes, existing consumers of a contract it changes, size (changed lines,
code + tests + docs), acceptance tests ("flip" is an existing check whose expected value changes).

Shared-file edit order: `scripts/builder-codex-pass.sh` C1, C2, C3, C4, C12, C9 (C12 and C9 both edit the
Sites refusal, `:1120`); `templates/_builder-brief-template.md` C2,
C4, C8, C9; `docs/review-loop.md` C2, C3; `templates/main-session.md` C7, C9; `scripts/seat.sh` C7, C9;
`builder-codex-pass-threshold.test.sh` C1, C2.

### C1 -- #376: a round missing a reviewer's verdict never clears an earlier P0 or P1 (~110 lines)

Port of host issue 3198, adapted to the plugin's Python `review_stop_id` and its abandoned-session record.

1. `session_proof`: on both exit-3 paths of an earlier pass (no reply, `:297-298`; a GitHub-read refusal, `:345-347`)
   print the session's start time (`stamp(began)`) before `sys.exit(3)`. Host prints it on the no-reply path only; the
   plugin's second exit-3 path is plugin-only (issue 316) and needs it too, or its round could not be placed.
2. `earlier_passes` (`:603-624`): read `round` (already read, `:603`). On rc 3, after the existing `CUT=mark` /
   `CUT=refuse` handling (unchanged), print `@ <tid> cut 0 0 <round> <began> <began> - - cut` and no finding lines,
   in place of `continue`. A start time of `-` or none dies, naming the thread, as host @@ -442 does. Header comment
   (`:583-597`) gains the `cut` row and "every reader skips or holds on kind cut".
3. `review_stop_id` (`:406-445`, Python): a `cut` row marks its round `cut` and adds no reviewer; a row whose eleventh
   field is `none` (a reply with no verdict) adds no reviewer either. A round is whole when its answering reviewers are
   exactly 1..n of its declared n (as today). A round that is not whole holds as an unknown P1 (one held line), at the
   place the walk reads its findings (the design branch reads it only for the latest design round, as today). A round
   that has a `cut` row from an abandoned launch AND a whole set of rows from its rerun is whole (plugin rule: the
   abandoned record "lets its round be run again", `:592-594`). Output shape unchanged: `review-stop-<unit>-r<N>` or
   nothing. Header comment (`:406-412`) names the three cases.
4. `--verify`: `ON_RECORD` (`:711`) and the chain loop (`:712-715`) skip `cut` rows (host @@ -583); the no-closing-pass
   loop (`:766-773`) dies on a `cut` row after the first pass: "its verdict is unknown, so it holds the merge" (host
   @@ -664). The launch's `EARLIER` list (`:970`) skips `cut` rows (host @@ -777), so a reviewer is never handed one.
5. Readers checked, unchanged: `passes_on_record` (`:400`, counts the round, as host wants: "a wholly cut-off round
   vanished from the count"), `open_findings` (`:633-635`: field 11 `cut` is not GO, so the round's P3s are not open
   ones; it has none), the first-pass check (`:734`, kind `full` only), `SOLO` (`:737`, kind `full`), the closing
   `C_TID` pick (`:1006`, kind `final`).

Produces: `earlier_passes` rows of kind `cut`; `session_proof` stdout on exit 3 (one line, the start time).
Consumes: `pass_threads` "<tid> <round>" lines (existing).
Existing consumers of the changed contract (the rows): `passes_on_record`, `review_stop_id`, `open_findings`, `--verify`
(`:661`, `:710-740`, `:752`, `:763-773`), the launch (`:969-977`, `:1013`, `:1591`, `:1600`). All in this file;
`rg -n 'earlier_passes' scripts hooks` lists no other file (2026-10-26).
Catches: a round with a reviewer's verdict missing (cut off, or a reply with no verdict) that today clears an earlier
P0 or P1, and a cut-off pass that today leaves the merge's no-closing-pass chain unrefused; no existing check sees a
round that has no row (A1).

Acceptance tests (`scripts/__tests__/builder-codex-pass-threshold.test.sh`, driving `review_stop_id` and
`earlier_passes` on rows and on fixture sessions, as its existing loop helpers do):
- new: "partial_round_keeps_p1_open: pass 7 with reviewer 1 of 3 GO does not clear the pass 6 P1; all three GO does"
- new: "a round whose every reviewer was cut off is on record as a cut row and holds the P1 before it"
- new: "a reply with no verdict does not count as its reviewer's verdict: the round holds"
- new: "a round run again after an abandoned launch clears the P1 before it" (What can go wrong row 1)
- new: "--verify refuses a cut-off pass after the first pass in the no-closing-pass chain, naming it"
- kept: every existing case of the file and of `builder-codex-pass-closing.test.sh`

Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- partial_round_keeps_p1_open -- scripts/builder-codex-pass.sh review_stop_id (the not-whole hold)
Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- a round whose every reviewer was cut off is on record as a cut row and holds the P1 before it -- scripts/builder-codex-pass.sh earlier_passes (the rc 3 cut row)

### C2 -- #377: no pass past the cap after a cap stop, and none on a plan-only change (~80 lines)

Port of host issue 3196. `cap_gate_reason <rows> <plan-only 0|1>` (awk, host @@ -794), placed right after the REVIEW
STOP gate (`:984`), before any scope or kind switch, so nothing is staged or committed:
- It prints nothing below the cap, when the latest round is a closing GO, or when a P0 or P1 is open (a `[P0]`/`[P1]`
  line, or a round that is not whole per C1, walking back over design rounds as `review_stop_id` does).
- It prints `code` when the latest round is a closing (`final`) round that is a cap stop by the pass's own rule: NO-GO,
  no P0 or P1, and at least one finding `cappable_count` counts (`:405`: P2 up to the blocking severity). The host says
  "NO-GO with only P2/P3"; the plugin uses its own cap-stop predicate (Decision 2), so a closing NO-GO that is no cap
  stop (only an untagged class line) is not refused, which is what `--verify` tells the Builder to do then (`:676`).
- It prints `plan` when the uncommitted change is non-empty and every path is under `.claude/plans/`, `.claude/briefs/`
  or `.claude/metrics/` (the folders `plan_only`, `:1029-1035`, reads).
- The refusal (exit 2): "this would be pass <n>, past the cap of <cap>, and no P0 or P1 is open: <the reason>. File
  the open findings and run merge-unit-local.sh <unit> --filed '<class>=#<n>', or write the code first. No pass
  starts, nothing was committed". `--check` reaches it too (the gate sits before `:1192`).

Produces: the refusal; no new file. Consumes: C1's rows (`cut`, field 11 `none`), `passes_on_record`, `cappable_count`,
`REVIEW_CAP`. Existing consumers: none (a new gate).
Catches: a pass launched after a cap stop, or a plan-only pass past the cap, which today runs as `final` (`:1012-1016`)
and spends a review on a loop already stopped; the merge's cap-stop check (`:671-678`) only reads the stop, and the
REVIEW STOP gate (`:984`) fires only on an open P0 or P1.
Docs: one line in the template's step 3 (`:200-204`), one in `docs/review-loop.md` (the cap paragraph).

Acceptance tests (`builder-codex-pass-threshold.test.sh`):
- new: "cap_stop_refuses_later_pass: after the pass 5 cap stop a design-only pass 6 is refused before any commit, and so
  is a code pass 6" (exit 2, HEAD unchanged, no round file)
- new: "past the cap a plan-only change is refused; the same change with code launches"
- new: "past the cap a closing NO-GO with no cappable finding is not a cap stop: the next closing pass launches"
  (What can go wrong row 5)
- new: "a closing GO at the cap does not refuse the narrowed pass after a later commit" (the exemption)
- new: "a P1 still open past the cap is never refused by the cap gate"
- flip: none; kept: the file's cap cases (section 10, `:203-223`)

Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- cap_stop_refuses_later_pass -- scripts/builder-codex-pass.sh the cap gate after the REVIEW STOP gate

### C3 -- #378: the fresh closing reviewer reads a clean copy of the branch (~262 lines)

Port of host issue 3195.

1. New `scripts/unit_folders.py`, the one home of the copy's path (host file, adapted): `scratch()` is `PP_SCRATCH`,
   else `COMMANDECK_SCRATCH`, else what `paths.sh` names (run as the host does); it raises when none gives one.
   `closing_root()` is `<scratch>/closing-copy`; `copy(wt)` is `<closing_root>/<basename of wt>`; `belongs(cwd, wt)` is
   true for a folder at or under the worktree or its copy, by path text or by realpath, false for a near name
   (`/ws/u2` for `/ws/u`). CLI: `unit_folders.py copy <worktree>` and `unit_folders.py root`. Standard library only.
2. `scripts/builder-codex-pass.sh`:
   - `session_proof` (`:217-218`, `:304`) and `pass_threads` (`:506-509`, the Claude branch `:522`, the Codex branch
     `:550`) take `$HERE` as one more argument, put it on `sys.path`, and test the session's cwd with `belongs`.
     So the merge (`--verify`, run by `merge-unit-local.sh:272`) takes a closing pass run in the copy, and refuses
     one run in another unit's copy (host lesson 2).
   - `stop_strays` (`:565-572`) matches a pass broker by ` --cwd <worktree> ` or ` --cwd <its copy> `: a closing
     pass's stray broker runs in the copy (plugin-only function; host has none).
   - After `trap 'pass_end $?' EXIT` (`:1406`): `CLOSING_COPY=$(python3 "$HERE/unit_folders.py" copy "$WT")`;
     `drop_copy` removes the copy with `git -C "$WT" worktree remove --force` (one `--force`: git refuses a locked
     worktree, A12), then `worktree prune`. It never runs a raw `rm -rf`. When git refuses and still lists the copy
     (a `worktree <path>` line of `git -C "$WT" worktree list --porcelain` equal to the copy's `pwd -P`; git lists the
     real path, A12), the copy is kept and one line names it: "closing copy <path> kept: git refused to remove it (a
     locked worktree?); nothing in it was removed", and `drop_copy` returns 1. A leftover folder git does not list goes
     through `pp_rm_rf` (`scripts/paths.sh:25`), which refuses a folder holding a `.git` (A12); its refusal is printed
     as is and `drop_copy` returns 1. So `scripts/builder-codex-pass.sh` stays off the raw-removal list of
     `scripts/__tests__/project-main.test.sh:90` (as `scripts/merge-queue.sh:68` does: git, then `pp_rm_rf`).
     When `FRESH` is set (`:1375`): drop a stale copy (a return of 1 dies before any reviewer: "the closing copy
     <path> is kept, so no closing pass starts; unlock or remove it, then run the pass again"; `COPY` is still unset,
     so the EXIT trap does not touch it), `git worktree add -q --detach <copy> "$SHA"`, link
     `node_modules` when the worktree has one, delete from the copy's working tree every
     `.claude/briefs/<unit>-r[0-9]*-*`, `<unit>-fix-r*.md`, `<unit>-handoff*.md`, `<unit>-after-r*.md` (the plugin's
     long-pass hand-off, `:1646`) and `<unit>-evidence.md`, find again, and die before any reviewer when one is left or
     a step fails. `COPY` is set only once the add succeeds. `RCWD=${COPY:-$WT}`. `pass_end` (`:1396-1405`) calls
     `drop_copy` when `COPY` is set (`|| true`: a kept copy is named, the pass's own exit code stands).
   - Codex: broker and companion `--cwd "$RCWD"` (`:1480`, `:1489`); `reviewer_session` greps `$RCWD` (`:1503`).
   - Claude reviewer (plugin-only, Decision 4): `cd "$RCWD"` (`:1460`), the git wrapper's `WT`/`WTP` bounds are the
     copy (`:1422`), and `tree()` and the HEAD check read the copy (`:1448`, `:1559`).
   - Every `python3` call of the copy path gets `PP_SCRATCH` from the environment `paths.sh` already exports
     (`scripts/paths.sh:74`).
   - The round files, prompts and raw outputs still go to `$WT/.claude/briefs` (`RUN`, `:1408`): only the reviewer's
     working folder moves.
3. `scripts/unit-cost.sh`: the Claude branch (`:22-24`) also reads the copy's Claude project folder,
   `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pp_slug "<copy>")`, the copy from `python3 "$PP_SCRIPTS/unit_folders.py"
   copy "$PP_WORKSPACES/$UNIT"` (no second spelling of the folder name, Decision 3): `files` is the `find` of both
   folders, and the "no sessions" line names both. The Codex line (`:108-113`) counts every `threads` row whose cwd
   `belongs` to the unit's worktree (`PYTHONPATH="$PP_SCRIPTS"`, as host @@ -111), not only `cwd = <worktree>`.
4. `scripts/dashboard_limit.py`: import `belongs` and `copy` beside the file (host @@ -51). The transcript selector
   (`got`, `:1359`) takes a request whose transcript is under `folder(w)` or `folder(copy(w))`, so a Claude closing
   reviewer's transcript (under the copy's project folder) reaches the stage filter; the per-unit stage costs (`mine`,
   `:1364-1365`) count a request when `belongs(folder, w)`. The day's cost per project (`owner`, `:1252-1253`) gets each
   project's closing root as one more root: `scripts/dashboard.sh:957` passes `[.path, .workspaces, .closingCopies]`,
   the project's `closingCopies` coming from `unit_folders.py root` run for that project (Assumption A8 says where).
5. Docs: `docs/review-loop.md`, the fresh closing pass paragraph: "it reviews a detached copy of the pass commit with
   the unit's round reports, hand-offs and evidence removed; the copy is deleted when the pass ends".

Produces: `scripts/unit_folders.py` (`belongs`, `copy`, `closing_root`, CLI `copy`, `root`); the copy folder, alive
only during a fresh closing pass.
Consumes: `FRESH` (`:1375`), `SHA`, `pass_end`, `PP_SCRATCH`.
Existing consumers of a changed contract (the cwd a closing reviewer's session records): `session_proof` and
`pass_threads` (both kinds), `stop_strays`, `reviewer_session`, `unit-cost.sh` (the Claude folder and the Codex
line), `dashboard_limit.py` (`got`, `mine`, `owner`).
Checked, not affected (they find a Codex WORKER pane's session by its pane's worktree, never a pass's):
`scripts/read-verdict.sh:262`, `scripts/orca-wait.sh:130`, `hooks/codex-dispatch.sh:224`. `scripts/unit-ledger.sh` binds
no Codex session by cwd (`rg -n codex scripts/unit-ledger.sh` empty, 2026-10-26).

Host lesson 1 (a test that copies a script and runs the copy): settled in Assumption A10; after this cut the Builder
runs the same `rg` again and adds `PYTHONPATH` to any copied run of a `unit_folders.py` reader it lists.

Acceptance tests:
- new file `scripts/__tests__/unit-folders.test.sh` (host's, adapted; every path absent on disk, as after a merge):
  "a closing-copy session counts as its unit's in the dashboard stages, and another unit's copy does not"; "with no
  scratch in the environment, the copy is the one under the scratch paths.sh names"; "with no scratch from the
  environment or paths.sh, asking whose a folder is raises"; "a folder under the copy or the worktree is the unit's; a
  same-prefix unit and its copy are not; an alias matches"; "the unit cost counts the closing copy's Codex sessions as
  the unit's"; "the day's cost counts a closing copy's request for its project"; "no code file but unit_folders.py
  spells the copy's folder name"; "claude_closing_copy_cost_counted: one Claude closing-review request with cwd
  `$PP_SCRATCH/closing-copy/u` and none in the worktree is counted for unit u by unit-cost.sh and by the dashboard
  stages" (one transcript under the copy's project folder, none under the worktree's; expects unit-cost's TOTAL line to
  count its turn and the unit's stage tally to count the request)
- new, `scripts/__tests__/builder-codex-pass-closing.test.sh`: "fresh_closing_pass_reads_a_clean_copy: the closing
  reviewer's --cwd is not the worktree, is gone after the verdict, and the merge still takes the pass";
  "closing_copy_holds_no_review_artifacts: at reviewer launch the copy holds no round report, fix hand-off, hand-off or
  evidence file, even one committed" (the fixture commits them with `add -f`; the companion stub logs what its cwd
  holds); "a stale closing copy from a killed pass is replaced" (What can go wrong row 3); "a closing pass whose copy
  cannot be made runs no reviewer and leaves no copy"; "closing_copy_locked_kept: a registered, locked closing copy
  holding an uncommitted tracked change survives the pass with its change intact" (the fixture adds the copy at
  `$PP_SCRATCH/closing-copy/u`, runs `git worktree lock` on it and changes a tracked file in it; expects the pass to
  exit non-zero with no reviewer launched, its output to name the copy as kept, and the file to hold the change)
- new, same file: "a Claude closing reviewer runs in the copy too, and the merge takes it" (with
  `codexReviewerAgent=claude`, as `builder-codex-pass.test.sh:167` sets it)
- kept: `builder-codex-pass-threshold.test.sh:218-220` (with `freshClosing` no, no copy: the reviewer is in the worktree);
  `project-main.test.sh:90-92` "only the scripts that remove their own mktemp folder use a raw rm -rf", its list unchanged

Break: scripts/__tests__/builder-codex-pass-closing.test.sh -- fresh_closing_pass_reads_a_clean_copy -- scripts/builder-codex-pass.sh RCWD (reverted to the worktree)
Break: scripts/__tests__/builder-codex-pass-closing.test.sh -- closing_copy_holds_no_review_artifacts -- scripts/builder-codex-pass.sh the artifact delete in the copy
Break: scripts/__tests__/unit-folders.test.sh -- a folder under the copy or the worktree is the unit's; a same-prefix unit and its copy are not; an alias matches -- scripts/unit_folders.py belongs
Break: scripts/__tests__/builder-codex-pass-closing.test.sh -- closing_copy_locked_kept -- scripts/builder-codex-pass.sh drop_copy (the still-listed check that keeps a copy git refused)

Catches: a fresh closing reviewer reading the unit's round reports, hand-offs and evidence, which today only a prompt
line asks it not to do (`FRESH_HEAD`, `:194`); no existing check sees what the reviewer's folder holds. The copy's
cleanup catches nothing new: it is bounded by git's own refusal and `pp_rm_rf`, the existing protections.

### C4 -- #379: a fix round names findings in separate files as parallel groups (~50 lines)

Port of host issue 3194; the script only names the groups (Decision 9). `fix_groups <round file>` (host's awk,
disjoint sets over every `path:line` a finding cites; a finding citing a file shared with another lands in its group;
a finding citing no file is in no group). In the hand-off, after `## What pass <N> found` (`:1689`): with two or more
groups, `## Parallel fix groups` with host's instruction text (one Agent helper per group with `isolation:
"worktree"`, only its findings and files; apply the diffs here in group order; on an overlap drop the parallel run and
fix the rest serially; run the round's tests once on the combined tree; a finding citing no file is yours; still one
commit and one pass), then the groups. Template: one line after `:246`.

Produces: a hand-off section. Consumes: the round file `$OUT`. Existing consumers: the fix brief's reader (the Builder);
`builder-fresh-round.sh` reads only the file name.
Catches: nothing new; it is a speed step (fix rounds run serially today). Its one guard, on an overlap drop the
parallel run and fix serially, plus one test run on the combined tree, keeps it from losing a fix the serial round
would make.

Acceptance tests (`scripts/__tests__/builder-codex-pass-class-return.test.sh`, which reads hand-offs with `hand`):
- new: "parallel_fix_groups: a NO-GO with findings citing a.sh and b.sh gives the hand-off two fix groups and the
  child-worktree rule; findings on one file give no group section"
- new: "a finding citing two files joins their groups"

Break: scripts/__tests__/builder-codex-pass-class-return.test.sh -- parallel_fix_groups -- scripts/builder-codex-pass.sh the two-group condition before the section

### C5 -- #380: main-watch stamps a round's next step only from a checked, current state (~95 lines)

Port of host issue 3197. The plugin has no `stop_next`; the port brings it as host has it after the fix (Decision 5).

1. `stop_next <worktree> <unit> <round>` before `report_wake`: one `timeout 60 bash "$HERE/builder-codex-pass.sh"
   --verify <worktree> <unit> HEAD` (stdout and stderr). Returns 1 (no stamp) on a timeout, or when the output does
   not name `<unit>-r<round>-reports.md` beside one of `Builder proof:`, `REVIEW STOP:`, `ended NO-GO`, `is a
   design-only pass` (the four forms `--verify` ends in: `:662`, `:672-676`, `:688`, `:781`, `:785`). Sets `SN_TEXT`
   for a REVIEW STOP (its decision id) or a cap stop (`; rule: cap stop`), else leaves it empty.
2. `report_wake` (`:921-945`): `newest_round` first. A round below the newest is stamped `superseded by pass <newest>;
   act on that report` and runs no arm. On the newest round, the `*:NO-GO`, `design:GO` and `adversarial:GO` arms call
   `stop_next`; a failure writes the note "<unit> pass <n>: stop check unreadable or timed out, report held" and
   stamps nothing this tick; `SN_TEXT` replaces the next step when set. After the arm, `newest_round` again: a round
   that appeared during the check means no stamp this tick (the next tick stamps this one superseded).
   `review:GO`, `final:GO` and `kind not recorded` keep their text (the plugin's own arms).
3. Fixture `scripts/__tests__/fixtures/main-watch-merge-setup.sh:7-11`: the fake verifier names the unit's newest
   round file (`<unit>-r<N>-reports.md`, N the highest in the worktree) in place of the fixed `r3`.

Produces: `stop_next` (exit 0/1, sets `SN_TEXT`); stamps of the new `superseded` text.
Consumes: `--verify`'s output forms (existing), `newest_round`, `note` (existing).
Existing consumers of a changed contract (the stamp text, the fake's line): `report_send` (sends lines 3 and 4 as they
are), `report_pending` (reads line 2), `main-watch-report-wake.test.sh` (the `rd` case's `refuse-rd` text becomes the
real design-only form, `rd-r1-reports.md is a design-only pass ...`: flip), `main-watch-auto-merge.test.sh`,
`main-watch-merge-gate.test.sh` (counts `--verify` calls of a unit with no round file: `stop_next` adds none there),
`main-watch-merge-restart.test.sh` (Assumption A7).
Catches: a next step stamped from a report's text alone when `--verify` says REVIEW STOP or cap stop, an older round's
report stamped as if it were current, and a stamp from a check that a newer round overtook; `report_wake` today runs
no check (`:921-945`), and the merge's own `--verify` runs only at merge time.

Acceptance tests (`scripts/__tests__/main-watch-report-wake.test.sh`):
- new: "stop_check_unreadable_holds_report: a stop check that names no round stamps nothing and notes it once"
- new: "older_report_stamped_superseded: r1 finishing after r2 is stamped superseded by pass 2"
- new: "newer_round_during_verify_not_stamped: a round that appears while the check runs leaves this tick with no stamp,
  and the next tick stamps the older one superseded" (What can go wrong row 2; the fake verifier writes r3 when called)
- new: "adversarial_go_review_stop_wins: a first-pass GO whose check says REVIEW STOP is stamped with the stop, not hand
  merge"
- flip: the `rd` case's refuse text (above); kept: every other case of the file

Break: scripts/__tests__/main-watch-report-wake.test.sh -- newer_round_during_verify_not_stamped -- scripts/main-watch.sh report_wake (the newest_round re-read after the arm)
Break: scripts/__tests__/main-watch-report-wake.test.sh -- stop_check_unreadable_holds_report -- scripts/main-watch.sh stop_next (the round-name and form check)

### C6 -- #381: a restarted main is told of every named seat run that is gone (~65 lines)

Port of host issue 3162's GONE lines (Decision 6). In `hooks/resume-context.sh`, before `left=` (`:127`):
- Names from the checkpoint `$cp`: each `seat.sh run <role> <unit>` (key `<unit>-<role>`) and each bare
  `seat-<unit>-<role>` token not followed by a file suffix (key `<unit>-<role>`; `seat-x.txt` is a record's file name,
  not a run), deduplicated.
- One `ps -axo command=` (the form `stop_strays` uses). Each `seat.sh run <role> <unit>` process gives a live key.
- Per name: not gone when its key is live, or `$PP_SCRATCH/seat-<key>.txt` holds a `collected=` line (`seat.sh:700`),
  or `$PP_SCRATCH/run-<key>.log` holds a `seat=` result line (`seat.sh:197`). Otherwise one line:
  `GONE: seat run <key> is named in the checkpoint but is not running and left no result; relaunch it`.
- `ps` failing prints one line `runs not checked: the process list could not be read, so the seat runs this checkpoint
  names may be gone; run bash scripts/seat.sh status <role> <unit> for each` and no GONE line.
- `PP_SCRATCH` comes from `paths.sh` (the hook sources it only in its `elif`, `:106`; the block sources it itself and
  skips with no line when it fails). The lines' bytes come off `left`, as `aged`'s do, and go into `out` (`:153`)
  after `aged`.

Produces: zero or more lines in the SessionStart block; no writes. Consumes: seat record and run log names
(`scripts/seat.sh:76`, `:172`), `PP_SCRATCH`. Existing consumers: none (new output lines; `clear-hook.log`'s
`payload_bytes` counts them as part of `out`).

Acceptance tests (`hooks/__tests__/resume-context.test.sh`):
- new: "a seat run the checkpoint names that is not running and left no result is posted as one GONE line"
- new: "a run with a collected record is not posted gone" (What can go wrong row 4)
- new: "a running run and one whose log holds its result line are not posted gone"
- new: "a seat record's file name is not a run name"
- new: "a process list that cannot be read prints one runs-not-checked line and no GONE line" (a PATH `ps` stub)
- new: "a checkpoint that names no run adds nothing to the block"

### C7 -- #382: the supported relaunch of a Builder whose pane is gone (~50 lines)

Port of host issue 3011 (Decision 7): no new verb; the route is a launch over the old record.
- `templates/main-session.md`, Do not -> instead (`:5-10`): "a Builder whose pane is gone (`seat.sh status builder
  <unit>` shows `pane=gone`) -> `bash scripts/orca-wait.sh --close <its task id>`, then `bash scripts/seat.sh launch
  builder <unit> <its newest hand-off or the brief>`; the launch writes the new pane's handle into the seat record, and
  the next fix round goes there".
- `scripts/seat.sh` `seat_status` (`:129`): adds `pane=live`, `pane=gone` or `pane=unknown` from one `orca-ide terminal
  list --json` (unknown when the list fails or the record has no handle). Read-only.

Produces: `pane=` in `seat.sh status`. Consumes: `orca-ide terminal list`. Existing consumers of `seat.sh status`
output: main and the Builder brief read it by eye; `rg -n 'seat.sh" status|seat.sh status' scripts hooks` lists no
script parsing it (2026-10-26; the Builder runs it again and lists any in the evidence).

Acceptance tests:
- new, `scripts/__tests__/seat-launch.test.sh` (after `:60`): "status on a Builder record whose pane is gone says
  pane=gone"; "a builder launch over a record whose pane is gone writes the new pane's handle"
- new, `scripts/__tests__/builder-codex-pass-fresh-round.test.sh` (after `:98`): "after a relaunch over a dead
  record, a NO-GO pass hands the fix round to the new pane" (the issue's done check)

### C8 -- #383: Builders keep a per-issue status table (~30 lines)

Port of host issue 3193. Template `:89-91` becomes: "The evidence file opens with an `Issue | Status` table, one
`| #<n> | not built |` row per issue of the batch, each set to `built` in the same edit that adds the section of the
cut that finishes it. The dashboard counts an issue built from a `built` row, or from a `## #<issue>` section with
something written under it." (both readers exist, `scripts/dashboard.sh:228-245`; the merge reads the table's
not-built rows as partial, `:247`).

Produces: a template rule. Consumes: `builder_progress` (unchanged).
Catches: a build whose evidence is written by cut showing no issue built on the dashboard until the end, and an issue
left not built at the merge (the table's not-built rows read as partial, `scripts/dashboard.sh:247`); with no
`## #<issue>` heading no existing reader sees either.
Acceptance tests:
- new, `scripts/__tests__/dashboard-built.test.sh`: "cut-evidence: a Builder writing evidence by cut counts the issues
  its status table marks built, mid-build" (no `## #n` heading; `.builder.built` lists the built rows only)
- new, `scripts/__tests__/brief-template.test.sh`: "the Builder template asks for an issue status table updated as each
  cut lands"

### C12 -- #391: class-sites files never hold a merged unit's worktree, and the refusal names the file it reads (~18 lines)

Native build from the issue's Fix and Test lines (spec section 4; no host commit). Built after C8 and before C9, which
edits the same refusal text.

1. Where the files live (the issue's choice, Decision 14): the plugin keeps every review record (round reports,
   prompts, raw reviewer outputs, hand-offs) uncommitted in `.claude/briefs/`, and the merge passes that folder by path
   (step 1 lets an untracked `.claude/briefs/*` through, `scripts/merge-unit-local.sh:210`; the cleanup skips a
   `?? .claude/briefs/*` line, `:160`). The class-sites files already live there and are written nowhere else, so
   neither a commit with the round nor a new ignore rule is added. Run 2026-10-26 (Assumption A11): a merged unit with
   both class-sites files untracked merged with exit 0 and its worktree was removed. The fix is the test that pins
   it, so a later change to either path check that would hold these files fails it.
2. The message (`scripts/builder-codex-pass.sh:1120`): the Sites refusal names
   `.claude/briefs/$UNIT-r$SM-class-sites.txt`, the file `CS` (`:1117`) it reads, in place of `-class-sites.md`.

Produces: one changed message. Consumes: `CS` (`:1117`). Existing consumers of the message: the Builder (by eye) and
`builder-codex-pass-class-sites.test.sh:21` (checks only the hit names: unchanged).

Acceptance tests:
- new, `scripts/__tests__/merge-unit-local-cleanup.test.sh` (last in the file): "class_sites_files_do_not_hold_cleanup:
  a unit whose passes wrote class-sites files merges and its worktree is removed by cleanup" (the unit's
  `<unit>-r1-class-sites.txt` and `.md` written untracked before the pass, as A11's run did; expects exit 0, the
  worktree gone, no `cleanup HELD` on the DONE line)
- new, `scripts/__tests__/builder-codex-pass-class-sites.test.sh` (beside `:20-21`): "the missing-sites refusal names
  the class-sites file the pass reads" (`-r2-class-sites.txt` in the refusal, no `-class-sites.md`)

Break: scripts/__tests__/merge-unit-local-cleanup.test.sh -- class_sites_files_do_not_hold_cleanup -- scripts/merge-unit-local.sh cleanup_step (the `?? .claude/briefs/*` skip)

### C9 -- the rule drift (~112 lines)

Section 3 lists all 35 lines. What it changes in the plugin:

1. `templates/_builder-brief-template.md`:
   - Before step 1 (`:178`): the prove step (R05): "Before step 1, once the build is done, you are asked: `Prove to me
     this works`. Run the changed behaviour through its real entry point with an input from the batch's done criteria
     (a script on a scratch input, a hook fed its event JSON, a page opened locally). Fix what it turns up and run it
     again. Under `## Proof` in the evidence file write one `Ran:` line and one `Saw:` line per thing proved, and a
     `Fixed:` line per fix. Nothing reverted; never production data or a deploy."
     Catches: a change whose tests are green but whose real entry point fails (a wrong path, a missing wiring, a hook
     that never fires on its real event); the tests and the review passes read the code and its fixtures, never the
     installed entry point run on a real input.
   - How to work: "The What can go wrong list of the batch or its plan binds: each case has its named test; a case a
     pass finds that the list lacks is added to the plan's list, with its test, in the commit of its fix" (R07);
     Catches: a case a pass found coming back untested in a later round, since no existing step writes it to the list
     every later pass and fix round is handed;
     "never a whole source file over 400 lines" joins `:46` (R07); "never find the runner by name with `pgrep`" joins
     `:101` (R07); "never open a generated file (a path `.gitattributes` marks `linguist-generated`); review its
     generator and test" joins the reviewer bullet `:36-42` (R11).
   - Sites lines (`:220`): `- <path>:<line> fixed, <how>` (R05; Decision 12).
   - Main-only list (`:227-229`): "every narrowed pass is handed that list; the closing pass is not, and main files
     what it finds again at the stop" (R05; matches `:1375`).
   - After the class rules (`:238`): "Ask main and wait only when the class fix would change something the brief names
     as a stated limit" (R05).
   - Done (`:268-272`): "a STOP line means run no fix round; main files what is open and merges. On `REVIEW STOP`, wait
     for main." (R06).
2. `scripts/builder-codex-pass.sh`: `break_gate`, its call and the template's break step stay (Decision 10). The
   Sites checks (`:1114`, `:1119`) and their die texts and the hand-off line (`:1681`, `:1691`) take
   `fixed, <how>` (Decision 12); this also fixes `:1119`'s sed, which today reads a `fixed, <how>` line as no site
   (its `fixed$` alternative needs the line to end there).
3. `scripts/seat.sh:416`: the plan-author prompt keeps its `Break:` clause (Decision 10) and gains "a `## Claims to falsify` list, one checkable claim per line" (R26: the pass hands that section to every
   reviewer, `:1371`, and no planner rule asks for it today).
4. `templates/main-session.md:88` (the plan judge's spec, R22): the judge also names the established practice for the
   problem and says whether the plan follows it (an unjustified departure is a finding, a justified cheaper one is
   not), and rejects a step added to the build, merge, review or push flow with no `Catches:` line.
   Catches: a plan that rebuilds what a standard practice already solves with no reason given, and a flow step that
   adds cost with no gap named; today's judge checklist (`:88`) asks neither.
5. `templates/global-rules.md`, Tests and planning (R22): a plan names file and symbol with an approximate line and
   re-checks them before the build; a plan step adding flexibility the request did not ask for is P1 when it adds a
   dependency or a config surface, P2 otherwise; a brief whose cuts run past an hour names its halfway cut, and the
   Builder writes a halfway note of about 200 tokens in the evidence file and goes on; sibling implementations are
   listed with a symbol tool (implementations of the contract, near-duplicates from a code graph), and the same edit
   to all of them is previewed first (a dry run) so none is missed; a unit over the size caps is not split without the
   owner's yes.
   Catches (the halfway note): a long build that loses its state to a context reset with nothing written since the
   plan; the evidence file today is written per issue, not at a fixed point. Catches (the sibling dry run): a sibling
   left out of a same-edit change, which a text search misses when the copy is renamed; no existing step lists
   siblings by tool or previews the edit.
6. `config/routing.json` (R12): `roles.builder` model `opus`, effort `medium`, note says so; `roles.orchestrator` note
   says main may make a small code fix itself (as `templates/main-session.md:11-13` already says).
   `config/recommended.json`: `builderModel` `opus`, `builderEffort` `medium` (Decision 11). README rows `builderModel`
   / `builderEffort` "(project: ...)" and `docs/configuration.md`'s Builder row follow (Assumption A9).

Produces: template, prompt and rule text; routing defaults. Consumes: nothing new.
Existing consumers of changed contracts: `seat-plan-marker.test.sh:34-35` (the prompt text: flip);
`brief-template.test.sh` (template pins: the Builder updates the ones whose text moved, each named in the evidence);
`plugin.test.sh:66` (recommended Builder model and effort: flip to `opus medium`); `doctor-options.test.sh:21-24`,
`plugin-option.test.sh:135-141` and `:196` (pin `sonnet` through their own config, not the default: run, expected
green); every test or fixture that writes a bare `- a.sh:1 fixed` Sites line for a pass after a NO-GO, each changed
to `fixed, <how>`: `builder-codex-pass-class-sites.test.sh:19` and its `sed` at `:22`,
`builder-codex-pass-class-return.test.sh:65`, `builder-codex-pass-threshold.test.sh:34` and `:177`,
`fixtures/builder-codex-pass-setup.sh:119`, `fixtures/merge-unit-local-setup.sh:101` (`rg -n -- ':[0-9]+ fixed\b'
scripts/__tests__`, 2026-10-26; the Builder runs it again after the change and it lists no bare line).

Acceptance tests:
- new, `builder-codex-pass-class-sites.test.sh`: "sites_fixed_needs_how: a bare fixed Sites line is refused and the
  refusal names the fixed, <how> form"; "a class-sites hit listed as fixed, <how> counts as listed"
- new, `brief-template.test.sh`: "the Builder template asks for the prove step before the first pass"; "the plan
  judge is asked for the established practice"
- flip, `seat-plan-marker.test.sh:34`: the prompt names the size line, the Test: line, the Break: line, the Claims to
  falsify list and the What can go wrong section
- flip, `plugin.test.sh:66`: the recommended Builder is `opus medium`
- kept, unchanged and green: the `break_gate` and `table_gate` checks (`builder-codex-pass.test.sh:222-240`)

Break: scripts/__tests__/builder-codex-pass-class-sites.test.sh -- sites_fixed_needs_how -- scripts/builder-codex-pass.sh the Sites regex (`fixed, .+`)

### C10 -- #388 and #389: stated limits, recorded (~8 lines)

- `hooks/dependency-addition-guard.sh` header (`:27-32`): one sentence, L1's case. `docs/hooks.md:17`: the same.
- `hooks/git-safety.sh` header (`:176-190`): one sentence, L2. `docs/hooks.md:13`: the same.
Acceptance: `bash ci/leak-test.sh` green; no behaviour changes (Decision 13). Both issues stay open: `Refs`.

### C11 -- release (~30 lines)

`.claude-plugin/plugin.json` `version`: the next free minor at merge time (0.51.0 today; `bash ci/version-check.sh`
decides). One CHANGELOG entry (section "Version and CHANGELOG").

## 3. Rule drift, line by line

"Host now" is the host section's current text in short; "plugin now" is the target's; "change" is what C9 does.
Lines whose map hash is "unsynced" were never synced, so the host text is compared whole with the plugin target.
After the merge, main records each line in the host's map (`rule-drift.py --sync <section>` for a ported or already
present line, `--only <section> <reason>` for a not-ported one); that is a host-side step, outside this diff (Decision 13).

| Line | Host section (drift key) -> plugin target | Host now | Plugin now | Change |
|---|---|---|---|---|
| R01 | short brief template, preamble -> `templates/_batch-brief-template.md` | Class line; optional `Closes:` line (or `Closes: none`); `Part: <n> of <m>` for a plan built part by part; a map check | `Closes:` line, and "leave the line out for an issue the unit only advances" (`:8-10`) | none for `Closes:` (present). Not ported: the Class line (the plugin picks the plan tier by trigger, `plan-tier.sh`), `Part:` (no part builds: `rg -n 'Part: ' scripts templates` empty), the map check (no such script) |
| R02 | brief template "Accepted failure modes (old heading)" -> none | heading renamed (R24) | n/a | none: a host map key to rename |
| R03 | brief template "Decisions (old heading)" -> none | renamed (R28) | n/a | none, as R02 |
| R04 | brief template "Stated limits (old heading)" -> none | renamed (R31) | n/a | none, as R02 |
| R05 | builder brief, passes section -> `templates/_builder-brief-template.md` How to work | the prove step; no break or mutation proof; the cap gate line; Parallel fix groups; Sites `fixed, <how>`; the Main-only list not handed to the closing pass; ask only when a class fix changes a stated limit; list `Out of scope:` lines; host test lanes and the advisor-free Builder | passes section `:171-246`: break-run step, bare `fixed`, Main-only to "every later pass"; advisor block (plugin option) | C9.1, C9.2 (prove step, `fixed, <how>`, Main-only, stated-limit ask), C2 (cap line), C4 (groups). Not ported: "no break or mutation proof" (not ported: the plugin keeps its break gate), `Out of scope:` (the plugin's passes print no such line: `rg -n 'Out of scope:' scripts` empty), the advisor-free rule (the plugin's advisor is an owner option), host paths and lanes |
| R06 | builder brief Done -> template Done | GO naming no P0-P2, or a STOP line: run no fix round, main files and merges; REVIEW STOP: wait for main | closing GO or a STOP line; no "run no fix round", no REVIEW STOP wait | C9.1 Done line |
| R07 | builder brief How to work -> template How to work | status per decision; ask, never guess; Prior art and Data design bind; What can go wrong binds; map before edit; Issue status table; helper caps; batch looks; read by range and symbol, never a whole file over 400 lines; Edit only; tests red first, no break proof; deployed-format test; test-run rules; never `pgrep` the runner; host offload, peer machines, lanes | `:25-169` carries all but: What can go wrong binds, the Issue status table, the 400-line read cap, the `pgrep` line, and it still asks for break runs | C9.1, C8, C9.2. Not ported: "no break proof" (not ported: the plugin keeps its break gate), host lanes, the PC offload, the peer test machine, the ring N-1 schema wording (the plugin's generic rule, `:92-94`, is the same rule), the plan line cap ("under 150 lines": the plugin's plan seat has none, and one-unit orders give plans of 900+ lines: `wc -l .claude/plans/plugin-open-issues-2026-10-26.md` = 955) |
| R08 | reviewer tools "A finding is a failing test" -> template How to work | failing test file per P0-P2; exact input or leave the finding out; a P2/P3 fix under ten lines as a diff, applied by main, checked by the other reviewer | `:36-37` and the pass's `FORMAT` (`scripts/builder-codex-pass.sh:117`) | none: present (the plugin's Builder applies the diff and the next pass reads it) |
| R09 | reviewer tools "Instruction priority and stopping" -> template | brief outranks startup file and skills; quote what stopped you; Orca `runtime_unavailable` in the sandbox is by design | `:38-40` | none: present |
| R10 | reviewer tools "Read cold" -> template | diff, brief, draft findings, then the evidence | `:40-42`, `templates/global-rules.md:26-27` | none: present |
| R11 | reviewer tools "Scope: the diff and its callers" -> template | open other files only to confirm or refute one finding; never open a generated file | `:41-42` (confirm or refute) | C9.1: the generated-file sentence |
| R12 | `routing.json#roles` -> `config/routing.json#roles` | Builder Opus at medium (was Sonnet high); main may edit code; no plan judge on Astra; Codex fast mode off everywhere | Builder `sonnet`/`high`; orchestrator note "never implements"; fast keys default false (`config/recommended.json`) | C9.6 (Decision 11). Not ported: the Astra seat (the plugin ships none) and the window-size notes (host settings files) |
| R13 | main-session preamble -> `templates/main-session.md` Working rules | "Rules for main only." (the injection sentence dropped) | the plugin's file has no such sentence (`:1-3`) | none |
| R14 | main-session "Orchestrator and Advisor Role" -> Working rules | coordinate and advise (code edits: Working rules); every test run, every wait over about 30 s and every command that can run in the background runs in the background | `:5-13` say both | none: present |
| R15 | main-session "Suggest tooling and workflow improvements" -> Working rules | new tools need approval; broken tooling is fixed now; suggest only with a count | `:116-117` | none: present |
| R16 | orchestration reference "Resource safety" -> `templates/global-rules.md` Working and review | node heap flag; test-lane limits; no duplicate agent; never launch agents with `setsid`/`nohup`; memory boxes and limits; resume, never restart; Mac vs PC figures | `:77-83`: no duplicate agent, resume never restart, memory not a count is the limit | none for the present rules. Not ported: host machine figures, lanes, boxes, cgroups, the heap flag; the `setsid`/`nohup` rule (the plugin opens every agent through an Orca pane, `seat.sh launch` and `builder-launch.sh`; its one detach, `seat.sh:171-180`, detaches a driver script, not an agent) |
| R17 | orchestration reference "Unit = one Orca worktree" -> global-rules | one unit one worktree one merge; units by code area; dispatch at once unless overlapping; verify every dispatch; worktree path and repo id | `:61-71` | none: present. Not ported: the host's paths and repo id |
| R18 | orchestration reference "Visibility and ledger" -> global-rules | every worker an openable pane; the task list is the ledger; reconcile what main did not start | `:70-71`, `:75-76` | none: present |
| R19 | adversarial reviews -> global-rules | same full scope for every reviewer; exact input or no finding; failing test; small fix as a diff; no reviewer test at round close; cold reads; no reviewer names in comments | `:12-34`, `:53-56` | none: present |
| R20 | comments rule (the tag word) -> global-rules | never write the tag in a comment | `:57-60` | none: present |
| R21 | orchestration rules preamble -> global-rules | the rules file points at a reference file per section | the plugin has one rules file, no reference file | not ported: no reference split in the plugin |
| R22 | planning rules -> global-rules | cite file ~line; freshness pass; integration surface; caps without a split; failing tests named; one map per unit; halfway checkpoint; review questions first; evidence as it goes; judge checks incl. established practice and Catches:; anti-over-engineering with P1/P2; dry-run output for fleet scripts; siblings by tool | `:100-122` has freshness, integration surface, siblings (no tool), review questions, evidence, over-engineering (no grade), acceptance tests; `templates/main-session.md:88` has the judge checklist without established practice or Catches: | C9.4, C9.5. Not ported: the judge checklist's dropped `Break:` line (not ported: the plugin keeps its break gate), the map file and its tools (no map in the plugin), the fleet dry-run rule (host environments), the plan-structure status script |
| R23 | startup file "Operating Rules" -> `templates/AGENT_STARTUP.md` | own the work; plan first; list callers before risky edits; fix every copy; never work round a refusal; confirm destructive actions | `:3-20` | none: present (the host's key-service item is host-only) |
| R24 | brief template "Accepted failure modes" (new heading) -> plan-author prompt `scripts/seat.sh:416-423` | one line each with `Test:`; reopened only on a counterexample | `Test:` line and the reopen rule are in the prompt | none: map to the prompt |
| R25 | brief template "Assumptions" -> plan-author prompt | each [likely]/[uncertain] claim settled or a Builder check with the action per outcome | in the prompt (`:418`) | none: map |
| R26 | brief template "Claims to falsify" -> plan-author prompt | one checkable claim per line; the judge tries each; every pass gets the list | read by the pass (`scripts/builder-codex-pass.sh:1371`), asked for by no planner rule | C9.3: the prompt asks for it |
| R27 | brief template "Data design" -> `templates/_batch-brief-template.md#Data design` | required; where the true copy lives, half-failed save, concurrent writes, retries | `:48-55` (richer) | none: map |
| R28 | brief template "Decisions" -> plan-author prompt | numbered, why with file ~line, `Test:` line | in the prompt | none: map |
| R29 | brief template "Plan change log" -> plan-author prompt | accepted judge findings, one line each, before the Builder | in the prompt | none: map |
| R30 | brief template "Prior art" -> `templates/_batch-brief-template.md#Prior art` | required; standard, library or service, why build | `:42-46` | none: map |
| R31 | brief template "Stated limits" -> plan-author prompt | measured bound: number, command, date | in the prompt (`:423`) | none: map |
| R32 | brief template "What can go wrong" -> plan-author prompt and batch template | five likeliest uncovered cases, each test in the acceptance test; reviewers and fix rounds get it | prompt `:418` and batch template `:57-64` | none: map |
| R33 | `routing.json#allowed-models` -> none | one list of allowed model ids | each role's allowed values are the plugin's option lists (`.claude-plugin/plugin.json` `userConfig`) | not ported: a second list would be a second copy of one fact |
| R34 | `routing.json#builder-cap` -> `/config` `maxBuilders` | 4 Builders at once on the host's Mac | the owner's `maxBuilders` option (`scripts/seat.sh:337-358`), no default | none: mapped; the host's number is that machine's, not ported |
| R35 | agents rules "Compact Instructions" -> `templates/global-claude.md#Compact Instructions` | keep task, evidence, cut, last round and findings, decision ids, files; drop dumps | `:111-115`, the same | none: map |

## Data design

- The closing copy: lives at `<scratch>/closing-copy/<worktree name>` (`unit_folders.py copy`), with git's worktree
  record in the project's `.git/worktrees/`. Written by a fresh closing pass only (`git worktree add`, then the
  artifact delete). Read by the closing reviewers (their working folder) and, by path text alone, by `belongs`
  (session_proof, pass_threads, stop_strays, unit-cost, the dashboard). Reset: removed and pruned by `pass_end` on every
  exit, and by the next fresh closing pass before it adds one (a SIGKILLed pass leaves it: L4). Removal is git's (one
  `--force`) or, for a folder git does not list, `pp_rm_rf`; a copy git refuses (a locked one) is kept, named, and
  stops the next closing pass until it is unlocked or removed (accepted failure mode 6). A retry is the next
  closing pass, which removes and re-adds. A half write (add or delete failing) dies before any reviewer starts; the
  EXIT trap removes what was made. Two concurrent writes: none, the pass lock (`:938-963`) holds one pass per worktree.
  Retries owned by the Builder (it reruns the pass).
- `cut` rows: derived on each read from the reviewer's session files and the abandoned marks; nothing stored.
- main-watch stamps (`$ST/due-<key>`): unchanged store and temp-then-`mv` publish; the change is which text is
  written and when nothing is written (a held tick). A held tick's retry is the next tick.
- The issue status table: rows in the Builder's evidence file, written by the Builder, read by `builder_progress` and
  the merge (unchanged readers).
- `seat.sh status` `pane=`: read-only. GONE lines: printed, not stored.
- Routing and recommended defaults: `config/routing.json`, `config/recommended.json`, read by setup and `pp_route_json`
  as today.

## Prior art

git's own linked worktrees (`git worktree add --detach`) give the clean checkout at one commit; no copy tool is
added. Grouping findings that share a file is a disjoint-set (union-find) pass, the host's awk. Every cut ports the
host's reference implementation in commit `b4f8dccf`, adapted to the plugin's files; nothing is redesigned.

## Decisions

1. **A round short of its declared reviewers, wholly cut off, or with a reply that gave no verdict holds as an unknown
   P1 and clears nothing; a round run again after an abandoned launch is whole once its rows cover every declared
   reviewer.** The host's rule (host @@ -464); the rerun clause is the plugin's own abandoned-record rule
   (`scripts/builder-codex-pass.sh:592-594`), which the host has no twin of. Test: "partial_round_keeps_p1_open: ..."
   and "a round run again after an abandoned launch clears the P1 before it"
2. **The cap gate refuses exactly a cap stop as the pass itself prints it (`:1603-1605`: NO-GO, no P0 or P1, a
   cappable finding), not "a NO-GO with only P2/P3".** With the blocking severity an owner setting, the two differ;
   using the pass's predicate keeps the gate and `--verify`'s "run the closing pass again" (`:676`) from contradicting.
   Test: "past the cap a closing NO-GO with no cappable finding is not a cap stop: the next closing pass launches"
3. **`scripts/unit_folders.py` is the one home of the copy's path, and no other code file spells its folder name.** Host
   design, kept; the fence check makes a second rule fail a test. Test: "no code file but unit_folders.py spells the
   copy's folder name"
4. **The Claude reviewer (plugin-only) runs in the copy too: its working folder, its git wrapper's bounds and the tree
   check are the copy's.** A Claude closing reviewer in the worktree would read the round files the host fix exists to
   hide. Test: "a Claude closing reviewer runs in the copy too, and the merge takes it"
5. **main-watch gains the host's `stop_next` as part of #380.** The issue's fix ("only a recognised answer bound to the
   report's round may produce a stamp") is defined over that check; without it the plugin's first-pass GO and NO-GO
   stamps ignore a REVIEW STOP. Only the newest round's NO-GO, design GO and first-pass GO call it, as host. Test:
   "adversarial_go_review_stop_wins: ..."
6. **#381's twin is the GONE lines only; the run state is the seat record's `collected=` line, the run log's result
   line, or a live `seat.sh run` process.** The detach half already exists (`scripts/seat.sh:171-180`). The plugin has
   no `long-job.sh`, so its records stand in for host's `long-job.sh list`. Test: "a seat run the checkpoint names that
   is not running and left no result is posted as one GONE line"
7. **#382 adds no relaunch verb: the supported route is `orca-wait.sh --close` and `seat.sh launch builder` over the old
   record, and `seat.sh status` shows `pane=`.** Host issue 3011 chose the same (a doc line and a pin); the status
   field is how main sees the pane is gone, which the host's status already shows. Test: "a builder launch over a record
   whose pane is gone writes the new pane's handle"
8. **#383 changes only the template; `builder_progress` already reads the table.** (`scripts/dashboard.sh:228-245`.)
   Test: "cut-evidence: a Builder writing evidence by cut counts the issues its status table marks built, mid-build"
9. **The parallel fix groups are named in the hand-off only; no script step, lock or commit is added.** Host issue
   3194's choice, and the owner's order covers only what the host built. Test: "parallel_fix_groups: ..."
10. **The plugin keeps its break-run gate (the owner's answer, 2026-10-26, spec section 5).** The host's current
    builder brief and planning rules drop break proofs (R05, R07, R22); those parts are not ported. `break_gate`, the
    template's break step, `docs/review-loop.md:12-14` and the plan-author prompt's `Break:` clause stay as they are.
    This plan's `Break:` lines are this unit's only red runs (the owner's newer order): before pass 1 the Builder runs
    each red with its condition removed, writes the gate's `- <test file> -- <check label> -- red: <command>` line under
    `## Break runs` and a `Mutation-verified: <test file> -- <check label>: RED, <how>` line beside it in the evidence
    file, then restores the condition. The evidence file is never committed, so `brief-template.test.sh:132` (no
    `Mutation-verified` in templates, hooks or scripts) is untouched. Test: the existing `break_gate` and `table_gate` checks (`builder-codex-pass.test.sh:222-240`) stay green, and
    `seat-plan-marker.test.sh:34` still names the Break: line
11. **The Builder's default model and effort become Opus at medium (routing and the recommended set).** R12; the
    plugin's recommended set is defined as the host's configured settings (0.49.0). Test: flip `plugin.test.sh:66`
12. **A Sites `fixed` line must say how (`fixed, <how>`).** R05; the regexes, die texts and hand-off text change; the
    `findings_so_far` "fixed in pass" tail (host issue 3168 F3) is not ported: the plugin's hand-off groups findings by
    class (`:1666-1670`), with no per-file history to add it to. Test: "sites_fixed_needs_how: ..."
13. **#388 and #389 change no behaviour, and the host map's sync records are main's step in the host after the merge.**
    The order says record only; this unit's diff is the plugin's. Test: none, text only (`bash ci/leak-test.sh` checks
    the wording)
14. **#391: the class-sites files stay where the plugin keeps every review record, uncommitted in `.claude/briefs/`;
    neither committed with the round nor given a new ignore rule.** The spec asks for the choice that matches the
    plugin's other review records; those are never committed (`stage_and_check`, `scripts/builder-codex-pass.sh:1174-1175`)
    and the merge passes that folder by path (`scripts/merge-unit-local.sh:160`, `:210`), which also covers a project
    that does not ignore `.claude/`. Committing them would put review scratch into the squash; an ignore rule would be a
    second mechanism for a folder already handled. Test: "class_sites_files_do_not_hold_cleanup: ..."
15. **The closing copy's cleanup never runs a raw `rm -rf`: git removes it (one `--force`), a copy git refuses is kept
    and named, and a folder git does not list goes through `pp_rm_rf`.** A raw fallback would delete a locked
    worktree's work, which git's refusal exists to keep (A12), and would put the pass on the raw-removal list
    `project-main.test.sh:90-92` forbids; `scripts/merge-queue.sh:68` already removes its copy this way. Test:
    "closing_copy_locked_kept: a registered, locked closing copy holding an uncommitted tracked change survives the
    pass with its change intact"
16. **A Claude closing reviewer's cost is read where its transcript is: the copy's Claude project folder.** Claude Code
    files a session under its cwd's slug (`scripts/dashboard_limit.py:1350`, `scripts/unit-cost.sh:22`), so both
    earlier selectors take the copy's folder beside the worktree's; the Codex index carries the cwd itself, so its
    reader needs only `belongs`. Test: "claude_closing_copy_cost_counted: one Claude closing-review request with cwd
    `$PP_SCRATCH/closing-copy/u` and none in the worktree is counted for unit u by unit-cost.sh and by the dashboard
    stages"

## Accepted failure modes

1. A closing copy left by a SIGKILLed pass stays until the next fresh closing pass of that worktree removes it (L4).
   Test: "a stale closing copy from a killed pass is replaced"
2. A GONE line for a run main stopped by hand with no collect (no live process, no `collected=`, no result line) is a
   false alarm; it is one advice line and starts nothing. Test: none, advice only; the checks above pin the three
   not-gone states
3. `stop_next` costs one `--verify` call (60 s cap) per newest NO-GO, design GO or first-pass GO round, once per round
   (the stamp guard, `:927`); a held tick asks again next tick. Test: "stop_check_unreadable_holds_report: ..."
4. Between `git worktree add` and the first reviewer, the copy appears in `git worktree list` of the project; nothing in
   the plugin treats that list as its units (`rg -n 'worktree list' scripts hooks`: Orca's list, the git-safety
   owner check and the relay lookup, 2026-10-26). Test: none, no reader
5. A merged unit's class-sites files are not archived: the merge archives only the brief, evidence, rulings, cap and
   round-report files (`pp_unit_briefs`, `scripts/paths.sh:1328-1336`), so they go with the worktree, as the round's
   prompts and raw reviewer outputs do. The round report keeps every `Class search:` line they came from. Test: none,
   unchanged behaviour; "class_sites_files_do_not_hold_cleanup: ..." pins that they never hold the removal
6. A closing copy git refuses to remove (someone locked it) is kept and stops every later fresh closing pass of that
   worktree, each naming it, until it is unlocked or removed by hand; nothing in it is lost. Test:
   "closing_copy_locked_kept: ..."

## Assumptions (each settled, or a Builder check with the action per outcome)

- A1 [settled] The plugin's `review_stop_id` already holds when a round has a row per answering reviewer and is short.
  Run 2026-10-26 (the function extracted with `sed -n '/^review_stop_id() {/,/^}/p'`, UNIT=u, REVIEW_CAP=5, rows
  `@ t<r><k> full <k> <n> <r> ...`): rounds 1-5 GO, 6 P1, 7 one of three GO -> `review-stop-u-r7`; 7 three of three GO
  -> nothing; 7 wholly cut (no row) -> nothing; 5 P1, 6 GO whole, 7 one of three GO -> nothing. So the gaps are the
  missing `cut` row and the short round not holding (C1).
- A2 [settled] `PP_SCRATCH` is exported (`scripts/paths.sh:74`) and the pass already shares it with main (it reads
  main's seat record at `$PP_SCRATCH/seat-$UNIT-builder.txt`, `:1386`), so the pass and the merge name one copy path.
- A3 [settled] The pass test fixture's companion stub records the `--cwd` it is given as the session's cwd
  (`scripts/__tests__/fixtures/builder-codex-pass-setup.sh:33`, `:42`), so the copy's sessions carry the copy's path.
- A4 [settled] The pass never commits `.claude/briefs` (`stage_and_check`, `:1174-1175`); the delete in the copy acts
  only on brief files a project tracks itself, as host's does on committed ones.
- A5 [settled] L1 and L2 as measured in Stated limits.
- A6 [settled] A detached seat run's command line is `bash <scripts>/seat.sh run <role> <unit> <spec> --marker ...`
  (`scripts/seat.sh:179`); its log is `run-<unit>-<role>.log` and its record `seat-<unit>-<role>.txt` (`:172`, `:76`,
  with no `SEAT_REPO` prefix for a run in this project).
- A7 [Builder check, before C5] Run `main-watch-auto-merge.test.sh`, `main-watch-merge-gate.test.sh`,
  `main-watch-merge-restart.test.sh` and `main-watch-report-wake.test.sh` after the fixture change. All green: go on.
  One red on a `--verify` count or a stamp text: the stamp guard ran `stop_next` for a unit with a round file the case
  did not expect; give that case's fake a round-naming answer (as the fixture does), never change `stop_next`.
- A8 [Builder check, before C3 step 4] `rg -n 'workspaces' scripts/dashboard.sh` around the `--project` writer of
  `project.json`. If that writer runs with the project's `PP_SCRATCH` (it runs `dashboard.sh --project` under
  `COMMANDECK_MAIN=<project>`, `:1165`, `:1175`): add `closingCopies` there from `unit_folders.py root`. If not: compute it
  in `dashboard.sh` per project path with `COMMANDECK_MAIN=<path> python3 scripts/unit_folders.py root`. Either way the
  test "the day's cost counts a closing copy's request for its project" decides.
- A9 [Builder check, before C9.6] `rg -n 'sonnet|Sonnet' README.md docs skills/setup/SKILL.md config`: every line that
  names the Builder's DEFAULT model or effort changes to Opus / medium; a line naming sonnet as an allowed value, or
  another role, stays. List each in the evidence.
- A10 [settled] Tests that copy a script and run the copy: `rg -n 'cp .*scripts/\*\.sh' scripts/__tests__` lists
  `run-shell-tests.test.sh:164`, `peer-offload.test.sh:20` and `relay-order.test.sh:122`, which copy `scripts/*.sh` (no
  `.py`) and run `run-shell-tests.sh`, `peer-offload.sh` and `relay-order.sh`, none of which reaches a `unit_folders.py`
  reader; every other copy is a whole `cp -R scripts` (for example `merge-unit-local.test.sh:248`,
  `dashboard-serve.test.sh:242`, `orca-wait.test.sh:86`), which takes the module along. No test copies
  `builder-codex-pass.sh`, `unit-cost.sh` or `dashboard_limit.py` alone (`rg -n 'cp .*(builder-codex-pass|unit-cost|dashboard_limit)'`
  empty, 2026-10-26). The Builder runs both searches again after C3.
- A11 [settled] #391's symptom does not reproduce in the plugin. Run 2026-10-26 on the merge fixture
  (`scripts/__tests__/fixtures/merge-unit-local-setup.sh`, whose project ignores no `.claude/briefs`): `mk k1`, then
  `k1-r1-class-sites.txt` and `.md` written untracked in its `.claude/briefs/`, `go k1`, `merge k1`. `git status` listed
  both files as `??` beside the round's prompts and raw outputs; the merge exited 0, its DONE line had no `cleanup
  HELD`, the worktree was removed, and the archive held `k1.md`, `k1-evidence.md`, `k1-r1-reports.md`. So C12 pins the
  behaviour and fixes the message; it does not change where the files go.
- A12 [settled] The copy cleanup's premises, run 2026-10-26 with git 2.55.0 in a scratch repository: a linked worktree
  added with `git worktree add -q --detach ../cc/u HEAD`, then `git worktree lock ../cc/u` and a tracked file changed in
  it. `git worktree remove --force ../cc/u` exited 128 ("fatal: cannot remove a locked working tree; use 'remove -f
  -f' to override or unlock first"), the change stayed, and `git worktree list --porcelain` still listed it.
  `pp_rm_rf` on that folder printed "paths.sh: refusing to remove ...: it is or holds a checkout or git data ...",
  exited 1, and the change stayed (its `.git` file). A worktree added through a `/tmp/...` path is listed by its real
  path `/private/tmp/...`, so the still-listed check compares the copy's `pwd -P`.

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| a round run again after an abandoned launch | round 7 has a `cut` row from the abandoned launch and three GO rows from the rerun; round 6 held a P1 | round 7 is whole and clears the P1: no stop | a round run again after an abandoned launch clears the P1 before it |
| a newer round lands while the stop check runs | r2 NO-GO is newest; the fake verifier writes r3 when called | no stamp this tick; next tick r2 is stamped superseded by pass 3 | newer_round_during_verify_not_stamped |
| a killed closing pass left its copy | a copy folder and git record at the copy path from an earlier pass | the next fresh closing pass removes it, adds a fresh one, and the reviewers run in the new one | a stale closing copy from a killed pass is replaced |
| a merged unit whose passes wrote class-sites files | NO-GO passes left `<unit>-r<N>-class-sites.txt` and `.md` untracked in the worktree's `.claude/briefs/` | the merge exits 0 and cleanup removes the worktree with no hold | class_sites_files_do_not_hold_cleanup |
| a closing NO-GO past the cap that is no cap stop | pass 5 final NO-GO naming only an untagged class line | the cap gate prints nothing; pass 6 final launches | past the cap a closing NO-GO with no cappable finding is not a cap stop: the next closing pass launches |

## Claims to falsify

- `review_stop_id`'s output is unchanged in shape (`review-stop-<unit>-r<N>` or nothing) and every caller reads it as
  before (`:661-662`, `:977-984`, `:1591-1595`).
- A `cut` row reaches no reviewer's prompt and no `Earlier pass ... ended` line, so the closing pass's handed list and
  `--verify`'s record list still match.
- The merge (`--verify`) takes a fresh closing pass run in its own copy and refuses one run in another unit's copy.
- No code file under `scripts/` or `hooks/` but `scripts/unit_folders.py` spells `closing-copy`.
- With `freshClosing` no, or on any other pass kind, no copy is made and the reviewers run in the worktree.
- `break_gate`, `table_gate` and their refusals are unchanged by this unit.
- `stop_next` adds no `--verify` call for a unit with no finished round file.
- `builder_progress` is unchanged; the template's table is a shape it already reads.
- The plugin's default Builder change touches only the defaults: a project that set `builderModel` keeps it.

## Not ordered (found, not planned)

- #384, #385, #386, #387, #390: their host fixes are not built yet; the plugin ports by host commit. Left open.
- Host issue 3168 F3's `findings_so_far` "fixed in pass" tail: Decision 12 says why it is not ported.
- #389's premise (a clean check before the forced remove) is host code from host issue 3181, which is not in the
  plugin; L2 records the plugin's real bound. A clean check itself is not ordered.
- The host map's renamed and unmapped keys (R02-R04, R24-R35) are fixed in the host's map, by main.

## Version and CHANGELOG

Version: the next free minor at merge time (0.51.0 if nothing lands first; `bash ci/version-check.sh` decides).
One entry, in the release-note style (topic sections named for what a user sees, plain sentences, no file names,
paths, issue numbers or hashes). Draft:

```
## 0.51.0 -- <merge date>

### Review loop

- A review round that is missing a reviewer's verdict no longer clears an earlier serious finding: it counts as one still open.
- Once the pass limit is reached and no serious finding is open, a new pass is refused after the loop has stopped, and so is a pass over a change that touches only the plan.
- The fresh closing reviewer now reads a clean copy of the branch with the earlier rounds' reports and notes left out. The copy is removed when the pass ends, the merge accepts that pass, and its cost is counted with the build.
- A fix round whose findings touch separate files now lists them as groups that can be fixed side by side.
- A site marked fixed after a failed pass now has to say how it was fixed.
- When a pass refuses because a searched site is missing from the checked list, it now names the file that holds the full list of sites.

### Main

- A report of an older review round now says which newer round replaced it, and no next step is posted from a check that could not be read or that changed while it ran.
- A main that restarts is told about every seat run its checkpoint names that stopped with no result.
- The seat status shows when a pane is gone, and the rules say how to start a Builder again in a new pane.

### Builders and plans

- Builders now run on Opus at medium effort by default.
- A Builder keeps a table of its issues, so the units view shows each issue as built when its part lands.
- Before the first review pass a Builder runs the change for real and writes what it ran and saw.
- Plans now list the claims a reviewer should try to disprove, and plan judges ask whether a plan follows the usual practice for its problem.
```

## Merge commit message

```
feat(plugin-port-2026-10-26): port the drifted rule sections and the host's review-loop and watcher fixes

Closes #376
Closes #377
Closes #378
Closes #379
Closes #380
Closes #381
Closes #382
Closes #383
Closes #391
Refs #388
Refs #389
```

An issue the progress notes leave `partial` moves from `Closes` to `Refs`.

## Progress notes (the Builder keeps one line per issue in the evidence file's Issue status table)

```
#376: built | partial -- <what is left>
#377: built | partial -- <what is left>
#378: built | partial -- <what is left>
#379: built | partial -- <what is left>
#380: built | partial -- <what is left>
#381: built | partial -- <what is left>
#382: built | partial -- <what is left>
#383: built | partial -- <what is left>
#391: built | partial -- <what is left>
#388: recorded (stated limit; stays open)
#389: recorded (stated limit; stays open)
```

## Files edited

Code (12): `scripts/builder-codex-pass.sh`, `scripts/unit_folders.py` (new), `scripts/unit-cost.sh`,
`scripts/dashboard_limit.py`, `scripts/dashboard.sh`, `scripts/main-watch.sh`, `scripts/seat.sh`,
`hooks/resume-context.sh`, `hooks/dependency-addition-guard.sh` (comment), `hooks/git-safety.sh` (comment),
`config/routing.json`, `config/recommended.json`.
Templates and docs (9): `templates/_builder-brief-template.md`, `templates/main-session.md`,
`templates/global-rules.md`, `README.md`, `docs/review-loop.md`, `docs/configuration.md`, `docs/hooks.md`,
`CHANGELOG.md`, `.claude-plugin/plugin.json`.
Tests (17): `scripts/__tests__/builder-codex-pass-threshold.test.sh`, `builder-codex-pass-closing.test.sh`,
`unit-folders.test.sh` (new), `builder-codex-pass-class-return.test.sh`,
`builder-codex-pass-class-sites.test.sh`, `builder-codex-pass-fresh-round.test.sh`, `fixtures/main-watch-merge-setup.sh`,
`fixtures/builder-codex-pass-setup.sh`, `fixtures/merge-unit-local-setup.sh`, `merge-unit-local-cleanup.test.sh`,
`main-watch-report-wake.test.sh`, `seat-launch.test.sh`, `dashboard-built.test.sh`, `brief-template.test.sh`,
`seat-plan-marker.test.sh`, `plugin.test.sh`; `hooks/__tests__/resume-context.test.sh`.

## 5. Build order and size (changed lines, code + tests + docs, estimates)

| Cut | Lines |
|---|---|
| C1 #376 | 110 |
| C2 #377 | 80 |
| C3 #378 | 262 |
| C4 #379 | 50 |
| C5 #380 | 95 |
| C6 #381 | 65 |
| C7 #382 | 50 |
| C8 #383 | 30 |
| C12 #391 | 18 |
| C9 drift | 112 |
| C10 #388 #389 | 8 |
| C11 release | 7 + CHANGELOG |
| Total | about 890 |

Order: C1 before C2 (C2 reads C1's rows), C3 after C2 (same file, later lines), C4, then C5-C8 (independent), C12
after C4 (the pass script's Sites refusal), C9 after C2, C4 and C12 (template and pass-script lines they also touch),
C10, C11 last.

## Done when

- Every cut's named acceptance tests are green.
- `bash scripts/run-shell-tests.sh --changed main` green.
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- A closing (final) pass ends `VERDICT: GO` with no finding named.

## Question for the owner

None. The break-gate question is answered (Decision 10).

## Plan change log

- 2026-10-26: first version.
- 2026-10-26: #391 added by the owner's order (spec section 4) as cut C12, a native build: the symptom does not
  reproduce in the plugin (A11), so C12 pins the cleanup with a test and fixes the refusal's file name (Decision 14,
  accepted failure mode 5). Its What can go wrong row replaces the "a named run that finished" row (cap of five); that
  case's test stays in C6's acceptance tests. Closes, progress note and CHANGELOG line added.
- 2026-10-26: found while adding C12: Decision 12's `fixed, <how>` change breaks every test and fixture that writes a
  bare `fixed` Sites line, including two fixtures the first version did not list; C9 now names all seven lines and
  grows by 7 lines. Planned size 36 files, 870 lines -> 39 files, 895 lines.
- 2026-10-26: the owner's answer (spec section 5): keep the plugin's break-run gate. Decision 10 now keeps it; C9 no
  longer touches `break_gate`, the template's break step, `docs/review-loop.md:12-14` or the prompt's `Break:` clause;
  R05, R07 and R22 mark that part "not ported: the plugin keeps its break gate"; the break-gate tests stay as they are,
  and `builder-codex-pass.test.sh` leaves the file list; the CHANGELOG line about the break run is dropped; the
  Question for the owner is cleared. C9 157 -> 112 lines. Planned size 39 files, 895 lines -> 38 files, 850 lines.
- 2026-10-26: plan judge finding 1 (P1) accepted: `drop_copy` drops its raw `rm -rf` fallback; a copy git refuses
  (locked) is kept and named, an unlisted leftover goes through `pp_rm_rf` (C3 step 2, Decision 15, accepted failure
  mode 6, A12 settles the judge's [likely] refusal); test "closing_copy_locked_kept" and its `Break:` line added.
- 2026-10-26: plan judge finding 2 (P2) answered by the owner's newer order (red proofs for the `Break:` lines only):
  every `Break:` line and Decision 10 stay; the Tier line and Decision 10 now say how each break run is recorded
  (`Mutation-verified: <test file> -- <check label>: RED, <how>`, before pass 1).
- 2026-10-26: plan judge finding 3 (P2) accepted: `unit-cost.sh`'s Claude branch and `dashboard_limit.py`'s `got`
  selector also read the copy's Claude project folder (C3 steps 3-4, Decision 16); test
  "claude_closing_copy_cost_counted" added.
- 2026-10-26: plan judge finding 4 (P2) accepted: a `Catches:` line for every step this plan adds to the build, merge
  or review flow (C1, C2, C3, C4, C5, C8, the prove step, the What can go wrong rule, the judge checks, the halfway note,
  the sibling dry run). C3 225 -> 262 lines. Planned size 38 files, 850 lines -> 38 files, 890 lines.

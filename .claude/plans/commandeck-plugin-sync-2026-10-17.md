# Plan: commandeck-plugin-sync-2026-10-17 -- issue 155 setup gap, issue 156 Planning stage, collect's marker, the GNU-tools guard
## issue 155 against the code
| Done when | State | Where |
|---|---|---|
| Setup offers the registry file | missing | `scripts/setup.sh`: no `paved-road` anywhere |
| Brief template has the Prior art section | done | `templates/_batch-brief-template.md` ~13, `_builder-brief-template.md` ~14 |
| The brief check refuses a brief without it | done | `scripts/builder-launch.sh` ~69 |
| The review prompts carry the lens | done | `scripts/builder-codex-pass.sh` ~115 (`LENS`), ~168 (Codex passes), ~697 (Claude reviewer) |
| The audit dry run lists its areas | done | `scripts/platform-audit/run-audit.sh` ~8, ~16; `platform-audit.test.sh` ~3, ~30 |
| A test of the refusal | done | `scripts/__tests__/builder-launch.test.sh` ~93; lens test `builder-codex-pass.test.sh` ~154 |
1. `scripts/setup.sh` ~444, with the other `NOTES+=` lines (printed in a `--plan` and at the end of a run):
   `[ -e "$PP_MAIN/.claude/paved-road.md" ] || NOTES+=("paved road: no .claude/paved-road.md; start it from $IL_ROOT/templates/paved-road.md, which also says what .claude/paved-road-areas.tsv holds")`.
## issue 156: a unit's planning is its Planning stage, rebuilt each collect from what outlives the worktree (r1 P1)
Seat records (`$PP_SCRATCH/seat-*.txt`, never deleted: read-verdict.sh ~486), Claude transcripts under `~/.claude/projects/<slug of
<ws>/<u>-plan>` and Codex rollouts all survive `plan-worktree-close.sh` ~100. No figure depends on an earlier sample or on the worktree.
2. `scripts/dashboard.sh` new `plan_seats <base> [before-iso]` (~15 lines, beside `seat_role` ~144): every `seat-<base>-*.txt`
   with `unit=<base>` and `worktree=<base>-plan` (awk of ~148), launched before `before` when given. Each: `{role, task, launched (iso),
   model (--model in cmd=), effort (--effort <l>, or Codex's -c model_reasoning_effort=<l>, paths.sh ~342; r1 P2), session}`, joined
   by `taskId` to `$METRICS/seat-events.jsonl` for `completedAt` and the logged `model`. `session`: the record's `session=` (Claude
   id, seat.sh ~316), else the ledger row's `session` (item 3). Prints `{worktree: "$PP_WORKSPACES/<base>-plan", from: <earliest
   launched>, seats}` or null.
3. `scripts/seat-event.sh` ~79-84: the row gains `session: $SESSION` (the log path ~70; null without one), so a collected Codex judge,
   which has no `session=` in its record, is tied to its rollout file.
4. `scripts/dashboard.sh` loop ~230: a `<u>` named `*-plan` whose `${wt%-plan}/.git` exists is skipped: its parent's row carries the
   planning (r1 P3, one unit, one card; builder-launch.sh ~143 tolerates a refused close). Otherwise a `*-plan` worktree marked
   `commandeck-plan-of` = `${u%-plan}` (seat.sh ~211) reads `st='"planning"'` before ~266, age `seat_age` (today ~246 makes it
   `waiting-main`); the Builder branch ~271 still overrides. Row gains `plan: $(plan_seats "${u%-plan}")`; a Builder row gains
   `plan: $(plan_seats "$u" <its stageHistory[0].from>)` (~280), so a closed worktree's planning still joins its Builder.
5. `scripts/dashboard.sh` ~337 costs input: Builder rows `{unit, worktree, stages: stageHistory, plan}`; plan rows `{unit, worktree,
   stages: [], plan}`. ~350: `.plan.cost = $c[.unit]` on plan rows; on a Builder row with a planning stage in its cost, the same
   `{stage: "planning", from, to}` prepended to `.builder.stageHistory` (app.js ~333 pairs by index and `from`) and `.builder.startedAt`
   set to its `from` (app.js ~279 Total time, ~317 clock). `unit-cost.json` ~347 then keeps the planning inside `<u>`, so
   `finishedBuilds` ~351 carries it with no change.
6. `scripts/dashboard_limit.py` ~335 `requests()` and ~618 `codex_requests()`: each request also keeps its transcript path (a `file`
   map beside `cwd`; cache versions 6 -> 7 and 3 -> 4, an older cache read again, as their comments ~350/~639 do). With `folders`
   they return `(row, folder, file)`; the two day callers ~829/~834 take `r, f, _`.
7. `scripts/dashboard_limit.py` ~868 `unit_costs`: a unit's `plan` adds its worktree's rows (Claude folder of `plan.worktree`, Codex
   `under(f, [plan.worktree])`) as a first stage `{stage: "planning", from: plan.from, to: <first stage's from, or null>}` and into
   the total (sec from `plan.from`); with no stages the planning stage is the unit's only one. Output gains `seats`: per seat
   `{role, model, effort, from, to, **tally(its rows)}`, a row being the seat's when its file is `<folder>/<session>.jsonl` or under
   `<folder>/<session>/` (helpers, subagents), or equals the seat's Codex path; to = `completedAt`, else its last row. Rows no
   seat holds (an uncollected Codex judge) are one `{role: null}` entry, so the seats always sum to the planning stage.
8. `dashboard/app.js` ~297: `if (u.plan)`: the `ucost` line (Total time from `plan.from`, `splitOf(plan.cost.total)`), then
   `costTable(u.plan.cost, ...)` (~495). Plan and Builder cards alike: an `ol.stagelist` row per `cost.seats` entry: role (`Not tied to
   a seat` for null), model + effort, calls, tokens in/out, `costOf`, time (`so far` with no `completedAt`). `planning` is already in
   STAGES ~14, STAGE_TONE ~57, STAGE_LABEL ~58.
## `seat.sh collect` after `wait --marker` (r1 P2)
9. `scripts/seat.sh` ~434 (`wait`): `sed -i '/^marker=/d' "$REC"; echo "marker=$MARKER" >> "$REC"`: the latest wait wins. ~525, after
   the silent-pane relaunch rewrote the record (~308): `echo "marker=$MARKER" >> "$REC"` beside `relaunched=1`. ~366 (`collect`):
   `[ -n "$DONE_MARKER" ] || DONE_MARKER=$(sed -n 's/^marker=//p' "$REC" | tail -1)`. Header ~7/~13, usage ~37: "collect falls back
   to the marker of the last wait". The STOP hints ~548/~552 already print `collect` with no `--marker`.
## `dashboard.sh` without GNU tools
10. No code: `scripts/paths.sh` ~49 (dashboard.sh ~33) stops every script on a Mac whose `stat`/`date` are not GNU (requirements.sh
    ~179-180), naming them and the setup command. Only the test below.
## Decisions
- issue 155: rung 2 (setup's NOTES list). Rejected: setup copying the template in (an owner file uninstall must then tell from setup's).
- issue 156: rung 2 (`unit_costs`, the request caches, seat records' `session=`, the seat ledger, the `planning` stage). Rejected: a
  planning snapshot written by plan-worktree-close.sh (a second writer of the cost file, and a close by hand would skip it).
- marker: rung 5 (a line each in wait, the relaunch and collect). Rejected: a role -> marker table in routing.json.
- GNU tools: rung 2, the paths.sh preflight. Rejected: portable calls in dashboard.sh (seat-event.sh ~58 and the rest need GNU too; README ~40).
## Tests (red first, all run by `scripts/run-shell-tests.sh`; `dashboard-view.test.sh` runs the .mjs)
- `seat.test.sh`: stub pane ends a finished turn on its marker. waits PLAN-DONE, REVISED, PLAN-DONE, then `collect` with no flag
  closes on PLAN-DONE (red: exit 3). `plan-judge-claude` (read-only), `COMMANDECK_SEAT_SILENT_SECONDS=1`, silent then marker: the
  relaunch happens, record holds `relaunched=1` and `marker=PLAN-DONE`, flagless `collect` closes. A plain relaunch drops the marker.
- `dashboard-built.test.sh` ~80, EMPTY `$CACHE`: records for pu's plan-author (Claude, `session=s1`), plan-judge-sol (cmd `-c
  model_reasoning_effort=high`, ledger row with its rollout path) and an uncollected judge; transcripts `s1.jsonl` + `s1/subagents/a.jsonl`
  under pu-plan's projects folder; rollouts with cwd `<ws>/pu-plan`. Worktree `pu-plan` REMOVED before the first sample; Builder `pu`
  live. First collect: `pu.builder.cost.stages[0]` planning with the fixture's calls and usd, `cost.seats` plan-author (subagent rows
  in its calls), plan-judge-sol effort `high`, one `role: null` entry, seats summing to the stage; `stageHistory[0]`, `startedAt`;
  finished build after merge the same. Live marked `pu-plan` with an idle pane: `planning` (red: `waiting-main`); with Builder
  `pu` also present: one `pu` row, no `pu-plan` row (r1 P3). Unmarked `foo-plan` stays `waiting-main`.
- `transcript-requests.test.sh`: a version-6 cache is read again and each row carries its transcript path; same for Codex 3 -> 4.
- `dashboard-view.test.mjs`: a plan card shows Planning, its `ucost` line, Cost by stage and one row per seat with calls and cost; a
  Builder card draws its planning segment first and lists the seats (red: no `Planning`).
- `requirements.test.sh`: setup `--plan` names `templates/paved-road.md`; with `.claude/paved-road.md` committed, no note. `go
  dashboard.sh` with a fake `uname` (Darwin), a fake BSD `stat` and an empty `COMMANDECK_BREW_PREFIX`: exit 1, `Mac preflight failed`,
  `GNU stat` named, no `project.json`. Green on arrival (item 10); red proof: the run with the `GNU stat` row deleted fails.
## Kept
`run-audit.sh`, `builder-launch.sh` ~69, the lens; `under()`; seat.sh's record format and `--marker` when given; paths.sh's preflight.
## Not doing
- No GNU check off the Mac (judge P2, rejected): Linux hosts ship GNU coreutils; a BSD `stat` first on a Linux PATH is hypothetical.
- No fast path for read-only Bash hooks, no duplicate heads-up post fix (out of scope).
## Risks
- A finished plan waiting on main reads Planning (the issue's ask). Seat records are keyed by unit name: a unit planned twice before
  its Builder counts both plannings' surviving records (shortcut, as dashboard.sh ~335; key by build if it matters).
- An uncollected Codex judge's spend shows under `Not tied to a seat` until collect writes its session. Cache bumps re-read 2 weeks of transcripts once.
- A reused pane (seat.sh ~232) keeps an old `marker=`; collect still takes a VERDICT first (~374).
## README / CHANGELOG
README ~473: "every worktree by stage" -> "..., a unit's planning as its Planning stage, seat by seat, counted in its build's cost";
setup section: one clause on the paved-road note. CHANGELOG `## Unreleased`: one entry each for items 1, 2-8, 9.
Planned size: 13 files, ~230 changed lines (dashboard.sh ~35, dashboard_limit.py ~40, app.js ~20, seat.sh ~5, seat-event.sh ~2, setup ~1, tests ~115, docs ~12).

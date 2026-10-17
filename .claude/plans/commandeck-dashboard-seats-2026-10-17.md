# Plan: commandeck-dashboard-seats-2026-10-17 -- plugin issue 168, its three carried ports, and reopened issue 167

Issue 167 joined this unit by the owner's ruling (relayed 2026-10-17): while a project's own watcher is live, the
plugin's watcher posts nothing, with the 0.13.1 heads-up fix's one-time note and crash window. It is item 9.
Item 10, the owner's (2026-10-17): one line telling the plan author to name a fitting skill when it is installed.

Issue numbers are written "issue 168" here: `ci/leak-test.sh` refuses a hash and three digits everywhere except
CHANGELOG.md. The same rule holds for code comments, tests and the README in the build.

The issue: a unit planned by two planners (later two judges) shows only its newest seat, its Planning stage shows
no time or cost while the seats run, and a running Codex seat's spend lands in "Not tied to a seat". The carry-over
comment's six locations, checked against today's code:

| Comment says | Today's code | Verdict |
|---|---|---|
| 1 `seat_costs()` ~875 tallies each seat | `dashboard_limit.py` ~875-899 | Right. No producer change; its input is item 5. |
| 2 `seatTags()` ~225, seats under `u.builder.cost.seats` | `seatTags` is drawn only by `buildBlock` ~623 (the Builder block). The planning card's head is `seatText(u, ...)` at `unitCard` ~271, fed `u.seat`: `dashboard.sh seat_actual` ~184, the worktree's newest Claude session. A planning card's seats are `u.plan.seats` (plan_seats) and `u.plan.cost.seats` (unit_costs). | Wrong function and wrong key for the planning card. |
| 3 the strip is `buildBlock` ~553; no `trace()` | `buildBlock` is the Builds panel, Builders only (`BUILD_STEPS` ~447 has no Planning). The stage strip is `unitCard`'s `trace` block ~320-371 (a variable, not a function). A Builder's Planning segment already draws (`dashboard.sh` ~387-391 prepends it); a planning card has no `stageHistory`, so `segs` is empty and its band has no figures. | Wrong place. |
| 4 no driver badge | `rg -i driver dashboard/ scripts/dashboard*.sh scripts/dashboard_builders.jq`: no hit. | Right: not applicable, no change. |
| 5 `seat.sh` ~348 binds only a Claude session | ~346-348 asks `read-verdict.sh --session`, which walks `claude` processes only. A Codex seat's `session=` comes only from the ledger row at collect (`plan_seats` ~177). | Right. |
| 6 `codex_requests()` ~622 walks one folder (~650) | The callers pass one folder: `build` ~825, ~841 and `unit_costs` ~922 get `${CODEX_HOME:-~/.codex}/sessions` (`dashboard.sh` ~375, ~745). The review home every session reader already searches (`read-verdict.sh` ~198 `~/.codex-review`) is never read for spend. | Right in effect; the fix is in the callers. |

## Items

1. Issue item 1 -- no change. `seat_costs` claims a request by the seat's `session` (id or absolute log path) and
   already tallies each seat. Item 5 gives a running Codex seat the `session` it lacks.
2. Issue item 2 -- `dashboard/app.js`.
   - `unitCard` ~271: a unit that is not a Builder and has `u.plan.seats` (non-empty) gets one entry per seat in the
     head's `.seat` span, joined by ` · `: `role, modelName(model) or "model not recorded", "<effort> effort" or
     "effort not recorded", running|done`. Done is `completedAt` set (collect), else running, the same clock as
     `seatsOf`'s "so far". Every other unit keeps `seatText(u, seatLabel(u))`.
   - `seatsOf` ~505: the role cell reads `<role>, running` while `s.to` is null. The grid (`app.css` ~382) is unchanged.
   - Comment ~498 and ~224: the head draws the plan's seats on a planning card; `u.seat` stays the Builder's own.
3. Issue item 3 -- `dashboard/app.js` `unitCard`.
   - ~321: `begun` is `u.plan.from` for a planning card (today null, so the clock starts at `stageSince`).
   - ~334: the segments' source is `u.builder.stageHistory` for a Builder, else `cost.stages` when `u.plan` has a
     cost. `cost.stages[0]` is `{stage: "planning", from: plan.from, to: null, ...tally}` (unit_costs ~959), so the
     match at ~337 is the same object, and the existing figures path (~350-352) draws its time ("so far") and cost.
   - Comment ~253-254: "a planning card's one stage is its Planning, from its cost".
4. Issue item 4 -- no change; stated in CHANGELOG as not applicable.
5. Issue item 5 -- `scripts/seat.sh`.
   - New `bind_session` beside `kv` ~110: when `$REC` has no `session=` line and `kv session` is not empty, append
     `session=<that log>`. One line.
   - `launch`, after the settle loop ~363: when the record has no `session=` (a Codex seat, or a Claude pid lookup
     that failed), `ST=$(worker_state_kv --launched "$LAUNCH_EPOCH" --spec "$TAG"); bind_session`. The tag picks this
     seat's log from a sibling's in the same planning worktree (the settle loop's own read does not pass it).
     `seat_codex_home` ~340 has already exported a routed home, so `codex_session_dirs` searches it.
   - `wait` ~577: `bind_session` after the existing `ST=` read, which already passes the tag. A Codex log written
     after the launch's one try binds on the wait's next poll, at no extra read.
   - `scripts/dashboard.sh` `plan_seats` comment ~158-159: session is "its Claude id or its bound log path, else the
     ledger row's". No code change there: `.[5]` already outranks `$r.session`.
6. Issue item 6 and port 2 -- `scripts/dashboard_limit.py`.
   - New module constant near `codex_requests`: `REVIEW_HOME = os.environ.get("COMMANDECK_CODEX_REVIEW_HOME") or
     os.path.expanduser("~/.codex-review")`, the same default every session reader searches.
   - New `codex_all(sessions, cache_dir, stem, since, now, missed, folders=False)`: `codex_requests` on `sessions`
     (cache `<stem>.json`) plus on `REVIEW_HOME/sessions` (cache `<stem>-review.json`) when that folder is not
     `sessions` itself. None only when both are None, else the two lists joined.
   - Callers: `build` ~825 (`codex-requests`), ~841 (same stem, `folders=True`), `unit_costs` ~922
     (`unit-codex`, then `or []`, keeping "no folder adds nothing").
   - `unit_costs` ~926, the `other` homes: add `os.path.join(REVIEW_HOME, "sessions")` to the `under(...)` roots
     beside `sessions` and `projects`. A seat bound to a review-home log is read by `codex_all` already; without
     this its home is read again (~927) and each request counts twice.
   - Docstring ~9-17: one line naming `COMMANDECK_CODEX_REVIEW_HOME`.
   - `scripts/dashboard.sh` ~930 `keep=(...)`: add `COMMANDECK_CODEX_REVIEW_HOME`, so the installed job sees an
     override set when it was installed.
7. Port 1 (an unsearchable sessions folder) -- `scripts/dashboard_limit.py`.
   - New `gone(path)` beside `under`: `os.stat`; True only on `FileNotFoundError` or `NotADirectoryError`, False on
     any other `OSError`. `os.path.isdir` is False for a folder whose parent cannot be searched, so today that
     folder reads as "not installed" and the week or unit reads complete.
   - `codex_requests` ~637: `if not sessions_dir or gone(sessions_dir): return None`. An unsearchable folder then
     reaches `os.walk`, whose `onerror` (`lost` ~636) appends it to `missed`, so the caller's `bool(missed)` marks
     the week, the day and the unit incomplete.
   - `unit_costs` ~930: `os.path.isdir(d)` becomes `not gone(d)` (another seat's Codex home), and ~943
     `os.path.isdir(folder(w))` becomes `not gone(folder(w))` (same defect for a worktree's Claude folder:
     `requests()` ~360 already turns an unlisted folder into None).
8. Port 3 (dispatch failed, pointer typed) -- `scripts/seat.sh` ~323, after `DIRECT=1`: `SPEC_TEXT+=" Task id $T."`.
   `worker_state --task` binds the session whose log holds the id (`read-verdict.sh` ~262), which `seat-event.sh`
   ~70 falls back to. A dispatched pane already gets the id in Orca's preamble. The record's prompt file (~351) is
   written after this line, so `wait` counts the marker against the text that was typed.
9. Issue 167 (reopened) -- `scripts/main-watch.sh`. Today only `heads_up_post` ~943 checks the claim; finished
   (~764), stopped (~767) and stalled (~673 `stall-`, ~757 `wait-`) items post as before.
   - `tick` ~1006, after `NOW=`: `CLAIMED=0; ! hu_claimed || CLAIMED=1`, read once a tick. The one-time line moves
     here from ~944-945 and widens: `main-watch: nothing is posted (finished, stopped, stalled, heads-up): pid
     <n> claims this checkout's items for <PP_MAIN> (<PP_SCRATCH>/heads-up-owner)`, still keyed by `$ST/hu-yield`.
     A tick with no claim removes `$ST/hu-yield` (moved from ~956).
   - `heads_up_post` ~943: `if hu_claimed` becomes `if [ "$CLAIMED" = 1 ]`; its seen-by-owner rule is unchanged.
   - `post` ~149, first lines, before any task is created: when `CLAIMED=1`, the item is not posted. Its first
     claimed sighting writes `$NOW` to `$ST/yield-<key>`. A later claimed tick whose `HU_AT` is past that time
     writes `handled` to `$ST/item-<key>`: the owner ran a whole cycle after the item was due, so it posted it.
     With no claim, `post` removes `$ST/yield-<key>` and runs as today. So an item the owner cannot have seen
     (its claim went stale first, the 300 s `HU_CLAIM_S` crash window) is posted once the claim ends, as a
     heads-up note is. The Builder-signal (~234) and process-count (~631) posts go through `post` too, so they
     also stand down: the ruling says nothing is posted.
   - Not gated: `builder_watch`'s typed nudge into a Builder pane and `mail_wake`/`wake`'s typed wake of main
     (neither is a post; main's ruling: keep both, a missed wake leaves main idle). Seat state (`mark_pane`, `grew_at`) still updates every tick, so the
     stall clocks stay right when the claim ends.
   - Header ~22-25 and the `hu_claimed` comment ~899-901: the claim stands this watcher down for every item.
     The file keeps its name `heads-up-owner`: a project watcher already writes it.
10. Owner item -- `templates/main-session.md` ~41, inside the "Plan before every build" bullet, after "Planners
    write the plan file (`.claude/plans/<file>.md`) and nothing else.". No plugin file speaks to a plan seat
    directly: main writes each planner's spec from this bullet, and `seat.sh` adds only the tag and the
    no-heartbeat line (~290-298). So this bullet is the planner's standing instruction. One added line:
    `Each planner's spec carries, word for word: "If the mattpocock-skills plugin is installed and one of its
    skills fits this unit (for example TDD for new logic, diagnosing-bugs for a bug), name it in the plan; the
    Builder uses what the plan names."`
    - It holds without the plugin: the sentence is conditional, and a plan seat sees that plugin's skills only
      when it is installed (`worktree-setup.sh` ~58 turns it off for the relay pane only).
    - The Builder reads the plan through the batch's `## Plan` section (`builder-launch.sh` ~75); nothing new on
      that side.
    - It stays inside the existing bullet, so `merge-rules.py` still counts the same rule units. That unit's id
      (sha1 of its text, ~106; `871dfc54` today) changes. `scripts/merge-rules.py` `MADE_FROM` ~112 gets
      `# 0.13.2 main-session.md` and `"<new id>": ("871dfc54",)`, the new id read from `--units` after the edit,
      so an owner whose saved `--drop 871dfc54` kept their own wording still gets no plugin copy.
11. Merge-check selection -- `scripts/run-shell-tests.sh` ~59, after the `.test.sh` case:
    `(hooks/__tests__/*.test.mjs|scripts/__tests__/*.test.mjs) t=${f%.mjs}.sh; [ ! -f "$t" ] || echo "$t" ;;`.
    Today a changed `.mjs` selects nothing, so the dashboard cases (a)-(c) would not run at merge. This maps a test
    module to its shell wrapper (`dashboard-view.test.sh`) for every later change too, not only this one.

## Tests (red first; each file is touched or selected through its wrapper, so the merge check runs it)
- `scripts/__tests__/dashboard-view.test.mjs` (selected through `dashboard-view.test.sh` by item 11).
  (a) New: a planning card with `u.plan.seats` = plan-author (Claude, `completedAt` set) and plan-judge-sol (Codex,
  running), and `u.seat` = the judge alone, as `seat_actual` gives the newest. The head's `.seat` text names both
  roles, each with its model, effort and done/running. Red today: it names only `u.seat`. This is the issue's
  "fails if only the newest seat is drawn".
  (b) Same card with `plan.cost` (the existing ~423 shape): `.lane.figs i` texts are `["120:00 so far"]` and
  `["$0.40"]`. Red today: no figures row.
  (c) Edit `SEAT_ROWS` ~419: `plan-judge-sol, running`. Red today.
- `scripts/__tests__/dashboard-built.test.sh`.
  Export `COMMANDECK_CODEX_REVIEW_HOME=$T/review-home` next to `HOME` ~16, so no case can read a real review home.
  (d) A review-home rollout (`xrow x-rev`, cwd `$WS/pv-plan`) in `$T/review-home/sessions/2026/10/17`: the unit's
  total calls count it (`unit_costs` called as the `homes` case ~151 does). Red today: not read.
  (d2) Same rollout, and the unit's plan seat has `session` = that rollout's absolute path: the unit's total calls
  and the seat's calls are each 1. Red without the item 6 exclusion: each reads 2.
  (e) A seat whose Codex home sits under `$T/locked`, made `chmod 000`, then restored: that unit's cost is None,
  never a number. And `codex_requests` on a sessions folder under the locked parent returns with `missed` not
  empty. Red today: the home reads as absent and the unit's total is complete. The trap restores the mode so
  `rm -rf` works.
- `scripts/__tests__/seat.test.sh` (same-name for `seat.sh`).
  (f) Reuse the judge-home fixture ~136-150 before its collect: `srun wait plan-judge-sol pu --marker PLAN-DONE
  --timeout-s 5` leaves `session=$JL` in the record. Red today: no `session=` line. A sibling rollout in the same
  home and worktree whose prompt holds another tag is not the one bound.
  (g) The Orca stub fails `orchestration dispatch` with a non-agent error when `$T/no-dispatch` exists, logs each
  `terminal send --text` to `$T/sent`, answers it with a `turn_started` receipt, and reads the pane idle for
  `pane_state_read` (`codex-helpers.sh`). A launch's typed text ends `Task id task_1.` Red today: it has no task id.
- `scripts/__tests__/main-watch-helper-hold.test.sh` (edited, so selected; `main-watch.sh` has no same-name test).
  Ticks use `COMMANDECK_NOW`; `claim`, `LIVE`, `offer` and `yields` ~142-161 are reused; `yields` greps the new line.
  (h) Each kind both ways, one fixture per kind, the claim live (`claim "$LIVE" "$REPO" $N`) then removed:
  finished (a planner's `PLAN-DONE`, as ~122), stopped (a Builder with no marker, as ~131), stalled (a `working`
  seat whose log and screen do not change across two ticks `STALL_S + 60` apart) and heads-up (existing ~145-150).
  Claimed: 0 posts for each, and exactly one stand-down line for the whole episode. Red today for finished,
  stopped and stalled: each posts. No claim: each posts once, as today.
  (i) Crash window: an item first seen under a claim whose `at=` then ages to `N - 301` is posted on the next tick.
  An item first seen under a claim, then a claimed tick with a later `at=`, then the claim removed: never posted.
  Each case also asserts 0 posts while the claim is live. Red today: both post at once.
- `scripts/__tests__/merge-rules.test.sh` (edited, so selected; it already reads `templates/main-session.md`).
  (j) The rule unit `MS --units` gives for "Plan before every build" holds `If the mattpocock-skills plugin is
  installed`, and the unit count is unchanged. Red today: no such line. The planner's rule is where main reads it.
  (j2) `MS --drop 871dfc54 | grep -c 'If the mattpocock-skills plugin'` is 0: an owner who kept their own planning
  rule does not get the reworded one. Red without the `MADE_FROM` line: 1.
- `scripts/__tests__/run-shell-tests.test.sh` (same-name for `run-shell-tests.sh`).
  (k) A fixture repo with `scripts/__tests__/view.test.mjs` and its wrapper `view.test.sh` (logs to `$RAN` like the
  others): editing only the `.mjs` runs `view`; an `.mjs` with no wrapper selects nothing. Red today: nothing runs.
- Each new case uses temp folders and no sleep over 5 s.

## Kept
- `seat_costs`, `plan_seats`' query and the record format: a bound log path is the shape `seat_costs` already
  claims (~886-888).
- `codex()` ~476: an unsearchable folder already reads "not measured" there.
- A Builder's card and the Builds panel: their Planning segment and `seatTags` stay as they are.
- The figures row shows time and cost per stage, as for a Builder; tokens per seat are in the seat rows.
- `hu_claimed`'s checks (live pid, this checkout as text, `at=` 0 to 300 s old) and the claim file's name and
  format: a project watcher already writes it.

## Not doing
- The push flow, CI workflows, any new flag.
- `read-verdict.sh` ~198, `orca-wait.sh` ~101, `dispatch-task.sh` ~66 and `hooks/codex-dispatch.sh` ~206 also name
  `~/.codex-review`; they do not honor the new override in this unit. Main's ruling: a follow-up issue, not this
  build (a user who sets the override gets spend from the new home while verdicts and waits search the default).
- A per-collect session lookup in `plan_seats`: one `read-verdict` call per running seat per collect.
- Item 10: no planning skill runs at unit start, and `templates/AGENT_STARTUP.md` ~32 (the short form of the
  planner rule) gets no copy: the owner asked for one line.

## Risks
- `main-watch.sh` ~473 builds `<projects>/<session>.jsonl` from a record's `session=`; a bound Codex log path
  makes no such file, so it falls back to its `read-verdict` lookup, as for a record with no session today.
- `builder-fresh-round.sh` ~78 reads the last `session=`; `bind_session` writes only when none exists.
- `dashboard-view.test.sh` skips without jsdom. The build must run it with `COMMANDECK_TEST_NODE_MODULES` set and
  say so in its evidence; a skip is not a pass.
- `chmod 000` cases pass vacuously as root; the suite already has such cases (`dashboard-built.test.sh` ~67).
- Item 9 widens what the claim means: a project watcher that writes it but posts only heads-ups would now silence
  this watcher's finished, stopped and stalled items. The README line says the claim covers every item; the
  project side must write it only when it posts all of them.
- A claim that stays live while the project watcher is hung (pid alive, `at=` refreshed) silences both watchers.
  Same limit as 0.13.1; the claim's own shortcut comment (~902) names the upgrade.
- Item 10's `MADE_FROM` line must carry the id `--units` prints after the final wording; a later rewording in
  the build changes it again. Test (j2) fails if the two drift.

## README / CHANGELOG
- README, Dashboard section (~477): one line, "A planning card lists every plan seat with its model, effort and
  state; `COMMANDECK_CODEX_REVIEW_HOME` (default `~/.codex-review`) names the review Codex home whose spend counts."
- CHANGELOG new patch entry: issue 168 (every plan seat drawn; Planning figures while seats run; a Codex seat
  binds its log; driver badge not applicable), the review home read for spend with its override, an unsearchable
  folder marks the week incomplete, a typed pointer carries the task id; issue 167 again: a live claim stands
  main-watch down for every item it posts, not only heads-ups; a planner names a fitting mattpocock-skills skill
  when that plugin is installed (an owner's saved drop of that rule still holds); a changed `.test.mjs` runs its
  `.test.sh` wrapper in the merge check.
- README ~224-226: the claim "stands the plugin's watcher down for every item it would post (finished, stopped,
  stalled, heads-up), not only heads-up notes; write it only on a cycle that posts all of them".

## Decisions (rung reached; option rejected)
- 1: rung 1, no change needed; rejected a producer change to `seat_costs`.
- 2: rung 2, `u.plan.seats` and `modelName` exist; rejected a new seat-chip component.
- 3: rung 2, the Builder's segment path fed `cost.stages`; rejected a separate planning band renderer.
- 4: rung 1, nothing to remove; rejected adding a guard for a badge that does not exist.
- 5: rung 2, `worker_state --spec` and `wait`'s existing poll; rejected a per-collect lookup in `plan_seats`, and a
  Codex process lookup like `pane_sessions`.
- 6: rung 2, one env default and one helper for three callers, and one more root in the existing `under` check
  for the double count; rejected a new `build`/`units` argument, and de-duplicating requests after the read.
- 7: rung 3, `os.stat`'s exception type; rejected `os.access` checks (wrong under ACLs, races the walk).
- 8: rung 5, one line; rejected sending the task id as a second typed message.
- 9: rung 2, `hu_claimed` and `post`, the one door every item goes through; rejected a claim check at each of the
  seven call sites, and marking every claimed item handled at once (loses an item the owner never saw).
- 10: rung 5, one sentence in the bullet main already briefs planners from; rejected a new bullet (a new merge
  rule id) and a line in `seat.sh`'s typed prompt (every seat role would get it); `MADE_FROM` is the existing
  answer to a reworded rule, rejected a CHANGELOG notice alone (it does not keep the owner's saved drop).
- 11: rung 2, the existing `case` in `run-shell-tests.sh`; rejected a comment-only touch of the wrapper (it fixes
  this build only, and the next `.mjs` change selects nothing again).

## Owner answers (settled by main)
- The four other readers of `~/.codex-review`: a follow-up issue (Not doing).
- Item 9: keep the typed nudge and the typed wake under a live claim; a missed wake leaves main idle.

Planned size: 16 files (`app.js`, `dashboard_limit.py`, `seat.sh`, `dashboard.sh`, `main-watch.sh`,
`main-session.md`, `merge-rules.py`, `run-shell-tests.sh`, six tests, README, CHANGELOG), about 215 changed lines.
The plan runs past 150 lines because the location table corrects three of six carried locations, and issue 167
and the owner's item joined the unit.

PLAN-DONE

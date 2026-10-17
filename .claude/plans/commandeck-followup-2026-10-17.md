# Plan: commandeck-followup-2026-10-17 -- plugin issues 157-164, 166 and 167, and the merge-unit-local header

Issue numbers are written "issue 157" here: `ci/leak-test.sh` refuses a hash and three digits everywhere except
CHANGELOG.md. The same rule holds for code comments, tests and the README in the build.

Shared fixes: issues 157 and 159 share `builder-fresh-round.sh` `tell()` (one edit gives the notice its type and
its re-run line). Issues 161 and 162 share one new jq def, `wtp`, beside `PP_PNORM` in `project-main.sh`: an Orca
list entry's worktree, whatever field holds it. Issues 158, 160 and 166 each filter in their own code (main-watch's
hold, orca-wait's jq, the poller's Python): no shared line, so three separate fixes. Issue 167 is its own fix in
main-watch's heads-up post. `to-main.sh` already finds main
by its worktree (`pp_seat_pane`, ~28) and stays as it is.

1. issue 157 `scripts/builder-fresh-round.sh`.
   - ~16: drop `LIMIT=900`.
   - ~29-37: the loop waits `idle 300000` (5 min a try) and does not give up while the pane is busy. After each failed
     try it asks `orca-ide terminal list --json` if `$H` is still listed and not `orphaned`. Gone: `fail "pane $H is
     gone; nothing typed"`. A list that fails or is not JSON counts as "still there", so it waits again. After each
     failed try it also sleeps `$SETTLE`, so an Orca that answers an error at once cannot make the loop spin. The
     settle check (SETTLE, then `idle 1000`) stays.
   - Judge r1 P2 (plan:94), a caller's test: `scripts/__tests__/builder-codex-pass.test.sh` ~229-232 expects `was not
     idle within 900s` from a pane that never idles. Its stub (~196) answers `terminal list` with nothing, which would
     now wait for good. The stub gets `*"terminal list"*`: it lists `term_frs` unless `FRS_GONE=1`. The case runs
     `FRS_IDLE=1 FRS_GONE=1` and expects `pane term_frs is gone; nothing typed`. `helper_done` still matches, because
     `fail` ends with "stays in the old session". The edited file is selected by the merge check.
   - New, before the loop: `exec 9>>"$PP_SCRATCH/fresh-round-$H.lock"; flock 9`. A second hand-off to the same pane
     waits until the first one exits, so the two never interleave.
   - Header ~8-10: "waits while the pane is busy, until the pane is gone". Self-test line: the new test file.
2. issue 157 + issue 159 `scripts/builder-fresh-round.sh` ~20-26 `tell()`: `to-main.sh escalation` becomes `to-main.sh
   question`. Cause confirmed: this file is the only `to-main.sh escalation` caller. Orca accepts a `question` from
   a pane with no dispatch; the Chief of Staff already sends one that way (`hooks/agent-startup-context.sh` ~116).
   The subject stays `fresh round not started: <hand-off file>`. The body becomes the reason, a newline, then
   `re-run: bash <scripts>/builder-fresh-round.sh <H> <HAND> [<REC>]`, each argument through `printf %q`.
3. issue 158 `scripts/main-watch.sh` `helper_out` ~184-191. The jq `select(.kind == "subagent")` with its STALL_S check on
   `seenAt` now also matches `(.kind == "codex" and $now - (.since | sub("\\.[0-9]+"; "") | fromdateiso8601) <
   $hold)`, with `--argjson hold "$HOLD_S"`. Judge r1 P1 (plan:28): `ep` is defined only in `dashboard_builders.jq`,
   not in this jq program, so the time parse is spelled inline, as the `seenAt` check at ~190 already does.
   Same change in the restart-clock select at ~700, so a pass started after the hold began restarts the clock too.
   Comment ~184: "a helper or a review pass". Cause is a little different from the issue: a pass writes only
   `codex-start` and `codex-end` rows (`builder-codex-pass.sh` ~917-926, the end row from its EXIT trap), so "recent
   log activity" cannot be read. The bound is HOLD_S (1 h) from the pass's start, plus the hold's own clock.
   A hard-killed pass, which leaves no end row, still gets posted.
4. issue 166 `scripts/cos-watch-inbox.sh` ~129-135 `mine`. A message whose `to_handle == me` (and that `me` did not send)
   is kept, whatever its run id, type or subject. The run check, the `worker_done` check, `want`/`coord` and the
   `main-watch|heads-up|main:|answer from main|seat` exclusions now apply only to all other messages. Both of the
   issue's causes are confirmed by reading the code (`answer-worker.sh` ~80 sends to `--to "$H"`). Header ~16-19 gets
   one line: "A message to this pane's own handle always counts."
   Judge r1 P2 (plan:34): the FYI hold at ~159 would still hold a direct message whose subject starts `FYI`, until
   some later message woke the pane. So `fyi` there also requires `m.get("to_handle") != me`: a message to this
   pane's own handle always wakes it, FYI or not.
5. issue 160 `scripts/orca-wait.sh`. These are the classifier lines:
   - `KEEP` ~245-262: `noisy` ~249-256, `harness` ~257-258, `own` ~260-261, and the final `select` ~262.
   - New `def owner: (((.subject // "") + "\n" + (.body // "")) | test($rid)) or (sender_unit == "Chief-of-Staff");`.
     The relay's pane is the one in `$PP_WORKSPACES/Chief-of-Staff` (`to-main.sh` ~17), and `handle_units` ~176-188
     already maps it, so this costs no extra call.
   - Judge r1 P1 (plan:41): `handle_units` ~183-184 reads only `.worktreePath`, so a relay pane listed with only
     `worktreeId` maps to nothing, and its plain answer stays hidden. Both `.worktreePath` reads there become `wtp`
     (item 6). The jq already starts with `$PP_PNORM`.
   - The final select becomes `select(relay or owner or (...))`.
   - `RID_RE` is defined once, near ~279: the ruling-id pattern from ~337. jq gets it through `--arg rid`, and the
     grep at ~337 uses it too.
   - ~515, after `kept=`: the non-heartbeat messages left out of `kept` are appended to `$MSGDIR/hidden.jsonl`. The
     jq is `[.result.messages[]? | select(.type != "heartbeat")] - $kept | .[]`. It is written before the next ack,
     as the kept bodies are. A failed write returns 1 without an ack, the same as ~519.
   - ~540: the line adds `; all but heartbeats are kept in $MSGDIR/hidden.jsonl`.
6. issue 161 + issue 162 `scripts/project-main.sh` ~55. `PP_PNORM` gets `def wtp: .worktreePath // ((.worktreeId // "") |
   capture("::(?<p>/.*)$").p) // ((.ptyId // "") | capture("::(?<p>/.*)@@").p);`. Every jq program that uses
   `PP_PNORM` can then call `wtp`.
7. issue 161 `scripts/project-main.sh` `pp_main_resolve` ~86-89. If `sp` is still empty after the `ORCA_WORKTREE_ID` step
   and `ORCA_TERMINAL_HANDLE` is set, it asks Orca: `sp=$(timeout 5 orca-ide terminal list --json | jq -r --arg h
   "$ORCA_TERMINAL_HANDLE" "$PP_PNORM"'first(... | select(.handle == $h) | wtp) // empty')`.
   - It also sets `PP_TRIED="$PWD${sp:+ $sp}"`.
   - Cause differs from the issue: no hook records a session's project. The run file is under the project's own
     scratch, so it cannot be read before the project is known. Orca's entry for this pane is the record that exists.
     The handle is an existing variable, so there is no new one.
   - `scripts/paths.sh` ~56: the message names `tried: $PP_TRIED`.
8. issue 162 `scripts/plan-worktree-close.sh` ~81 `panes()`: `(.worktreePath | pnorm)` becomes `(wtp | pnorm)`. Cause
   unconfirmed: no live list shows an entry without `worktreePath` (the 2026-10-17 list had it on every entry). But
   the code reads only that field, and the fix covers the issue's stated shape. See Not doing.
9. issue 163 `scripts/read-verdict.sh` `verdict_lines` END ~462-466. Cause confirmed by tracing the awk on the issue's
   screen: the plain reading ends inside a fence, and the cropped reading closes at the bare fence and returns GO.
   Fix: when the cropped reading replaces a plain reading that ended inside a fence, the screen is ambiguous, and a
   line whose word is `GO` (the same strip as `verdict_word` ~469-472) is dropped. Other verdicts are kept.
   CEILING comment ~442-444 is rewritten to say this. Why not the both-readings rule from `seat.sh unfenced` ~117:
   the issue's two regression screens have the same shape (prose, a bare fence, a verdict line). That rule reads
   both as no verdict, which fails the issue's own NO-GO case. Dropping only GO passes both cases (main's ruling,
   in Decisions).
10. issue 164 `scripts/merge-unit-local.sh` ~377-378 Builder row: add `SEAT_EVENT_SPEC=$(sed -n 's/^tag=//p' "$SEAT" |
    tail -1)` beside `SEAT_EVENT_STOP=done`, as `seat.sh` ~446 does. Cause confirmed by reading the code.
11. `scripts/merge-unit-local.sh` ~8 header: still names `scripts/__tests__/merge-unit-local.test.sh`. Item 10 brings
    that file back (one case), so the name is correct again. The line becomes `Self-test (the Builder's ledger row
    only; CI's full suite has no merge-path test): bash scripts/__tests__/merge-unit-local.test.sh`.
12. issue 167 `scripts/main-watch.sh`. The heads-up is Claude Code's own offer, which `heads_up_capture` ~803 reads
    from the machine's store, so a project watcher reading the same store posts the same note.
    Main's ruling after judge r1 (P1 plan:84, P2 plan:80): one owner, never two that yield, and no matching of
    process arguments. The plugin's watcher stands down only for a live claim.
    - The claim is `$PP_SCRATCH/heads-up-owner`, under the plugin's scratch for this checkout. It holds three
      lines: `pid=<n>`, `main=<full checkout path>` and `at=<epoch>`. A project watcher writes it, whole, each cycle
      in which it posts heads-up notes itself. A project watcher that yields writes none, so one of the two always
      posts. The plugin's watcher never writes it. `at=` is the freshness clock: it can be read against
      `COMMANDECK_NOW` with no `stat` (BSD and GNU differ).
    - New `hu_claimed` near `hu_done` ~886. It returns 0 only when all of these hold:
      - the file reads;
      - `pid` is all digits and `kill -0 "$pid"` succeeds;
      - `pp_norm "$main"` equals `pp_norm "$PP_MAIN"` as text, so a nested or other checkout never matches;
      - `NOW - at` is from 0 to `HU_CLAIM_S` (a new constant, 300 s, five plugin ticks).
      Anything else (missing, unreadable, dead pid, other path, stale or future `at`) is no claim, and the plugin
      posts as today.
    - `heads_up_post` ~915, first lines: on `hu_claimed`, each group not yet handled has its members' pairs and its
      key added to `$HU_DONE`, as `hu_done` ~892 writes them, with no post. Then the function returns. The claim
      owner is posting those notes, so they are not posted again when the claim ends.
    - The first claimed tick prints one line to the service log and writes the pid to `$ST/hu-yield`:
      `main-watch: heads-up notes are not posted: pid <n> claims them for <PP_MAIN> ($PP_SCRATCH/heads-up-owner)`. A
      tick with no live claim removes `$ST/hu-yield`, so a later episode says why again.
    - `heads_up_capture` still runs every tick, so the ledger and the archive (`$HU_LOG`) stay complete.
    - Header ~22-23: one clause, "unless a live claim in $PP_SCRATCH/heads-up-owner names another watcher".

## Tests (red first; the merge check selects each, as noted)
- New `scripts/__tests__/builder-fresh-round.test.sh` (same-name). The stub `orca-ide` fails `terminal wait` for the
  first 3 calls, then succeeds. It lists the handle unless `$T/gone` exists, and logs every `terminal send`. Runs
  with SETTLE=0 and no main pane, so `to-main.sh` queues the notice in `$SC/queue/main.jsonl`.
  (a) Busy 3 tries, then idle: `/clear` and the pointer are typed, exit 0. Red today: the first failed wait fails.
  (b) Pane gone: exit 1, nothing typed, the queued row has `.type == "question"` and a body holding `re-run: bash
  .../builder-fresh-round.sh term_x <hand>`. Red today: the type is escalation and there is no re-run line.
  (c) Two runs on one handle, the first held in `terminal wait` until the test touches a file. The send log reads
  `/clear`, pointer, `/clear`, pointer. Red today: the second run types into the first one's window.
- `scripts/__tests__/main-watch-helper-hold.test.sh` (edited, so selected). Ticks use `COMMANDECK_NOW`. A Builder
  stopped, no DONE, with an open `codex-start` 10 min old: no "stopped without reporting" post (red today). The same
  pass 61 min old: posted. With its `codex-end` row: posted at once.
  Issue 167, same file, one offer per case. The fixture's store is `$HOME/.claude/plugins/store`, holding a
  `cc-plugin-you-should-know_builtin-t.json` offer. The offer's session transcript has `cwd` set to the fixture
  checkout.
  The live pid is a `sleep 30 &` started by the test, killed in its trap. A dead pid is one that test started and
  waited for.
  (a) Plugin yields: a claim `pid=<live>`, `main=$REPO`, `at=$NOW`. Two ticks: no `heads-up:` send, and exactly one
  "heads-up notes are not posted" line. Red today: the note is posted.
  (b) The project yields: no claim file at all, as a project watcher that stands down leaves it. The note is posted
  as today. Then the claim from (a) is removed and a new offer arrives: the new one is posted and the (a) offer is
  not.
  (c) Stale claims, one tick each, a new offer each time, each posted: `at=$((NOW - 301))`; a dead pid;
  `main=$REPO/nested` (a nested checkout); and `main=` a different checkout.
  (d) A running process whose argv 0 is `$REPO/ops/main-watch.sh` (`bash -c 'sleep 30' "$REPO/ops/main-watch.sh" &`), with
  no claim: the note is posted. This guards the judge's r1 P2 case: a process that merely names the file is no owner.
- `scripts/__tests__/cos-tell.test.sh` (edited). `row()` takes an optional run id. A `status` message from `term_main`
  to `term_cos` with subject `answer from main` and an empty run id wakes the watcher (red today). One to `term_cos`
  with subject `FYI owner answer` and no later message also wakes it, and is printed (judge r1 P2; red today). The
  same run's `heads-up: x`, `main-watch: y` and a `worker_done`, all addressed to `run:run_1`, do not. An `FYI`
  sent to the run is still held.
- New `scripts/__tests__/orca-wait.test.sh` (same-name). The stub answers `orchestration check` with one batch, then
  one with no `deliveryId`. `terminal list` lists `term_cos` with only `worktreeId: "id::$WS/Chief-of-Staff"` and no
  `worktreePath`, the judge's r1 P1 shape.
  (o) A status from `term_cos` with subject `turn complete` and body `Owner says proceed`, with no ruling id, is shown
  (red today, and red with item 5's `owner` alone, before `handle_units` reads `wtp`).
  (a) A "turn complete" echo with no marker whose body cites `r-19991017-101010-1-a1b2c3` is shown (red today).
  (b) A status from `term_cos` with plain words, which `own` would drop when `ORCA_TERMINAL_HANDLE=term_cos`, is
  shown (red today).
  (c) A plain echo is hidden. The summary line names `hidden.jsonl`, and that file holds the echo, not the
  heartbeat (red today).
- `scripts/__tests__/project-main.test.sh` (edited; `project-main.sh` same-name).
  (a) Run from `$T/elsewhere` with `ORCA_WORKTREE_ID=` and `ORCA_TERMINAL_HANDLE=term_m`. The stub lists `term_m` with
  only `worktreeId: "id::$T/one"`. `orca-wait.sh --close task_3` closes it (red today).
  (b) The existing "no pane either" case unsets the handle, and checks that the message names `tried: $T/elsewhere`.
- `scripts/__tests__/plan-worktree-close.test.sh` (edited). The stub lists the pane with `worktreeId` and `ptyId` but
  no `worktreePath`. `--dry-run` prints `would close 1 panes`, and the real run closes that handle (red today: 0).
- New `scripts/__tests__/read-verdict.test.sh` (same-name). The stub's `terminal read` gives an empty accumulated
  stream and the screen. HOME has no session log, so the screen is read.
  (a) `"Reviewing.\n```\nVERDICT: GO\n"`: no verdict (red today: GO).
  (b) `"code\n```\nVERDICT: NO-GO\n"`: NO-GO.
  (c) A plain fenced sample, then the reply's own `VERDICT: GO` outside any fence: GO (guards against
  over-dropping).
- New `scripts/__tests__/merge-unit-local.test.sh` (same-name), one case. The fixture is cut down from the deleted
  file (`git show 3991506^:scripts/__tests__/merge-unit-local.test.sh` ~13-83: the stub Codex plugin, `mk`, `go`).
  Two seat records in one Builder worktree, each with its own `tag=`, and two session logs whose prompts carry those
  tags. After a GO merge, the Builder's ledger row names the Builder's session (red today: it can name the other).
  Target is under 15 s, measured at red. If it runs over 30 s, see Risks.
Each new or edited case runs in seconds: idle results, ticks and clocks come from stubs or `COMMANDECK_NOW`. The one
real sleep is SETTLE=0.

## Kept
`to-main.sh` (the lookup by worktree, the queue, exit 3). The two-idle settle check. The 120 s wait after `/clear`.
STALL_S for subagents. `seat.sh unfenced`. orca-wait's eight noise rules for every message that is not the
owner's. The poller's run-only rule for traffic to the run.

## Not doing
- The other `.worktreePath` readers (`paths.sh` ~454/~471, `main-watch.sh` ~341, `merge-unit-local.sh` ~394,
  `close-done-panes.sh` ~94, `hooks/lib/context-clear-restart.sh` ~30; `orca-wait.sh` ~183 moves in item 5).
  Issue 162's cause is
  unconfirmed, and each one touched needs its own selected test. Once a list without `worktreePath` is seen, they
  move to `wtp` as one follow-up issue.
- Out of scope, as the spec says: other `merge-unit-local.sh` behaviour, the push flow, CI, and new flags. (The owner
  withdrew the spec line that put the duplicate heads-up out of scope; it is now item 12.) No new environment
  variable. No hook that records a session's project (item 7 reads Orca).
- Issue 167: the watcher's other items (finished, stalled, stopped) still post. The issue's done-when covers only the
  heads-up note. No process-argument matching (main's ruling). No change to any project's own watcher: writing the
  claim is that project's side.
- No pid check on the pass lock for issue 158. It would read another script's lock internals; HOLD_S bounds the hold.

## Risks
- issue 157: a pane that stays busy forever, and is never closed, keeps the hand-off waiting in the background. That is
  what the issue asks for. The pane's own stall post (main-watch STALL_S) still reaches main.
- issue 160: `hidden.jsonl` only grows. `shortcut: one append-only file, rotate it per run if it grows past a few MB`.
- issue 161: the fallback adds up to 5 s, but only on the path that fails today. Hooks get `CLAUDE_PROJECT_DIR`, so they
  never reach it.
- issue 163: a NO-GO pass seen through an ambiguous screen can read as NO-GO when it was GO. The cost is one extra fix
  round, never a skipped one.
- issue 164: the one-case merge test runs the real pass script on stubs. If it runs over 30 s, it gets `# own-lane:` (the
  runner's marker), so the merge check runs it in its own lane and not in the guards shard.
- Issue 167: until a project's watcher writes the claim, both still post, as today. That is the safe failure: a
  duplicate, never a lost note. If the claim owner dies within 300 s of its last write, a note captured in that
  window is marked handled and not posted; it stays in `$HU_LOG`. A pid reused by another process within those
  300 s would pass `kill -0`: `shortcut: pid plus a 300 s at= window; add the process start time to the claim if
  a reuse is seen`.

## Docs
- README ~207: "posts a message ... when the Builder's pane stops (not while it waits on a helper or a review pass it
  started, for up to an hour)".
- README ~381 (`cos-watch-inbox.sh` row): "... or anyone sends to its own handle".
- README, after ~206-208 (the `main-watch.sh` paragraph), the claim contract for a project's own watcher, three
  lines: "A project that runs its own watcher and posts Claude Code's heads-up notes itself writes
  `<scratch>/heads-up-owner` (`pid=`, `main=` the full checkout path, `at=` epoch) each cycle it posts. While that
  claim is live (pid alive, same checkout, under 300 s old), this watcher posts no heads-up. A watcher that stands
  down writes no claim."
- CHANGELOG, a new top section `## Unreleased`: one line per issue (157-164, 166, 167), each with its `(#NNN)` as the
  file's entries have them. Also: "merge-unit-local.test.sh is back with one fast case: the Builder's ledger row".

## Decisions (rungs of the plugin's ponytail ladder: 1 need, 2 codebase, 3 stdlib, 4 dep, 5 one line, 6 minimum)
- issue 157: rung 6, the loop as it is plus a liveness check and `flock` (already a requirement). Rejected: a
  new retry-interval variable (the stub decides each try's result).
- issue 159: rung 5, one word, `question`, in `tell()`. Rejected: a new send path to main beside `to-main.sh`.
- issue 158: rung 2, the existing hold and HOLD_S. Rejected: reading the pass lock's pid. Main's ruling: keep the
  existing 1 h HOLD_S bound for an open pass, with no new knob.
- issue 166: rung 5, one `or` clause before the filters. Rejected: dropping `answer from main` from the exclusions, which
  would let main's answers to workers wake the relay.
- issue 160: rung 2, the existing `handle_units` map and the ruling-id pattern. Rejected: an extra `terminal list` call
  to find the relay's handle.
- issue 161: rung 2, Orca's list entry for this pane. Rejected: a SessionStart hook writing a session-to-project file.
- issue 162: rung 2, one jq def beside `PP_PNORM`. Rejected: a local fix in `panes()` only (issue 161 needs the same read).
- issue 163: rung 6, a few awk lines in END. Rejected: the both-readings rule (fails the issue's NO-GO case). Main's
  ruling: on an ambiguous screen, drop only a GO. A false NO-GO costs one extra round; a false GO skips one.
- issue 164: rung 5, one assignment. Rejected: a grep-the-script test (it cannot fail when behaviour changes).
- issue 167: rung 6, one small claim reader using `kill -0`, `pp_norm` and the existing `$HU_DONE`. This is main's
  ruling (one owner, live claim only). Rejected: process-argument matching. Judge r1 P2 showed an editor holding
  the file, or a nested checkout, would pass it, and with the other side yielding no one would post. Also rejected:
  telling main through `post`, which would give main a task to close for every yield episode. Also rejected: a new
  `main-watch.test.sh`, which would copy the hold test's whole harness.

## Judge r1 findings and their fixes
- P1 plan:84, both yield: item 12, the live claim. Tests: helper-hold 167 (a) and (b).
- P1 plan:28, `ep` undefined: item 3, the time parse spelled inline.
- P1 plan:41, relay pane without `worktreePath`: item 5, `handle_units` reads `wtp`. Test: orca-wait (o).
- P2 plan:80, argument match: item 12, no process matching. Tests: helper-hold 167 (c) and (d).
- P2 plan:34, an FYI to the pane's own handle held: item 4, the FYI hold skips those. Test: the cos-tell FYI case.
- P2 plan:94, the caller test: item 1, the `builder-codex-pass.test.sh` ~196 stub and the ~229-232 case.

## Questions for the owner
None open. Main ruled on issues 158 and 163 (see Decisions).

Planned size: 21 files (4 new tests), about 460 changed lines. Scripts about 95, the 4 new tests about 235, the 5
edited tests about 105 (`builder-codex-pass.test.sh` added), docs about 20, and this plan.
Over the 150-line plan target: ten issues each need their lines and red case, and the judge's six fixes add more.

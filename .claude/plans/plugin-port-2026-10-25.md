# Plan: plugin-port-2026-10-25 -- the host's merged tooling twins, issues 348 to 365, and the rule drift

Tier: Standard
Order: the owner, 2026-10-25, "do it" to the plugin-unit order: ONE plugin unit for the scope below
Closes: issue 350, issue 351, issue 352, issue 353, issue 354, issue 355, issue 356, issue 357, issue 358, issue 359, issue 360, issue 361, issue 362, issue 363, issue 364, issue 365
Closes (part B): issue 348, issue 349
Split: two parts (the owner approved a two-part split for this case, 2026-10-25)
- Planned size: ~84 files, ~2470 changed lines

**Over the cap, split in two.** The whole order is about 3,855 changed lines in ~109 files: section 5's ~3,665 for
the issue groups plus ~190 for the rule drift items (section "Rule drift items"). That is over the plugin's plan cap
(four cuts, 40 files, 20 edited owners) and over the 3,000-line review limit (`config/routing.json:101`,
`diffLines`). The owner approved two named parts, each its own unit with its own item list, build order and Done
when (section "Parts"):

| Part | Unit | Groups | Issues | ~Lines | ~Files |
|---|---|---|---|--:|--:|
| A | plugin-port-2026-10-25 (this plan file) | G1-G9, the drift items, local commit 6da84e5 | 350-365, host 3173, every drift line | ~2,470 | ~84 |
| B | plugin-port-mod-2026-10-25 | G10, G11 | 348, 349 | ~1,450 | ~25 |

Part A is still over the files cap (~84 of 40) and over 60 files: section "Question for Max" proposes an A1/A2 split
along group lines; this plan does not split it. Part B shares only `.claude-plugin/plugin.json`, `scripts/merge-unit-local.sh` and
`scripts/__tests__/plugin.test.sh` with part A, so part A merges first and part B launches on main after it. Main
copies section "Parts", part B, with G10, G11 and the cited assumptions, into `.claude/plans/plugin-port-mod-2026-10-25.md`
at part B's launch.

LOCAL merge only, no push. Base: main `6da84e5` (0.46.0). Every file:line below was read on `6da84e5`.
Launch: new unit plugin-port-2026-10-25

Public repo: no personal names, seat nicknames, host product name, host paths, ruling ids or `#<number>` issue
references in any shipped file, test, commit message or this plan (`ci/leak-words.txt`). Outside CHANGELOG.md a
plugin issue is written "issue N" and a host issue "host issue N". The batch brief (untracked) carries the `#` form
of the Closes line that `merge-unit-local.sh` parses.

Tests: changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), plus the files each group names
(the runner does not run a shared helper's callers' tests). No red-proof run, no `Mutation-verified:` line, no
test-timeout raise. Every review finding, P0 to P3, blocks the merge; done is a closing pass `VERDICT: GO` naming no
finding.

Port rule (the owner's order): a host item that merged on the host's local main is PORTED from the named host commit
(adapted to the plugin site, not redesigned). A plugin issue with no host commit is BUILT from its issue text, one
function or block per item, its comment naming the plugin issue, no plugin-only names inside the logic, so the host
can port it back.

Timed checks: `scripts/__tests__/builder-fresh-round.test.sh` (each run under `timeout 10`, :46 :108 :170),
`scripts/__tests__/answer-worker.test.sh` (`timeout 8`, :158), `scripts/__tests__/read-verdict.test.sh`
(`timeout 20`, :29 :53), `scripts/__tests__/to-main.test.sh` (`timeout 3`, :78). No heavy fixture goes into these
four; the new cases there use the existing stubs and go after the existing timed cases. The one heavy fixture (a real
rebase and test run, issue 356) goes in `scripts/__tests__/builder-codex-pass-rebase.test.sh`, which has no
time-bound check. The other new cases that build real git state (G2's report retry with its worktree removed and
the proof before the rebase, G8's worktree adds) go in `scripts/__tests__/main-watch-report-wake.test.sh` (new),
`scripts/__tests__/merge-unit-local.test.sh` and `hooks/__tests__/git-safety.test.sh`; `rg -n '\btimeout [0-9]'` on
those two and on `worktree-setup`, `plugin-option`, `update`, `install-lib-setup`, `brief-template` and the three
`builder-launch-resume-*` files this plan edits is empty (2026-10-25). Any other edited test file: the Builder runs
the same `rg` before adding a heavy case and, on a match, places the case after the timed ones.

Background runs (the owner's order for this unit, RD13): every test run in this unit, of any length, starts with Bash
`run_in_background`, and so does every other command that can run in the background; only quick reads stay in the
foreground.

## 0. Local commit 6da84e5

Rides in this unit (version bump and review). Nothing new is planned for it. Its changed tests are green on this
worktree, run 2026-10-25: `bash scripts/run-shell-tests.sh scripts/__tests__/plan-tier.test.sh
scripts/__tests__/answer-worker.test.sh` printed `2 passed, 0 failed, 0 parked` (plan-tier 20 s, answer-worker 42 s).
The closing run on the tip runs both again.

## 1. Item map (twin, verdict, site, change, test)

| Issue | Host twin | Verdict | Plugin site (~line) | Change | Test (file, case) |
|---|---|---|---|---|---|
| 345 | none | DROP, done in 0.46.0 | `templates/main-session.md:16`, `:55-64`; `templates/AGENT_STARTUP.md:20-21` | none: main already asks neither question; the 0.46.0 CHANGELOG entry closes it | `scripts/__tests__/brief-template.test.sh:79-85` (exists) |
| 348 | none | BUILD | new `.github/workflows/release.yml`, new `scripts/release-decide.sh`, new `scripts/release-notes.sh`, new `scripts/release-backfill.sh`; `scripts/update.sh:27` | tag and release per version through one decision script the workflow calls, backfill script | `scripts/__tests__/release-notes.test.sh` (new) "first, middle and last section", "a version with no section fails", "an unchanged version decides skip" |
| 349 | `c7aaf716` + `84118aa9` (host issue 3185; the v2 layout, stall removed) | PORT | new `hooks/units.tsx`, `hooks/units-sources.ts` + tests; `hooks/hooks.json:2`; `.claude-plugin/plugin.json` options; `types/index.d.ts`; `docs/dashboard.md`; `scripts/merge-unit-local.sh` touched tests | the units mod (v2 layout, no stall mechanic) and its merge gate | `hooks/units.test.tsx`, `hooks/units-sources.test.tsx` (ported cases); `scripts/__tests__/merge-unit-local.test.sh` "a changed hooks module runs claude plugin test" |
| 350 | `218bd2b1` Cut 3 (host issue 3174) | PORT | `hooks/ask-records-decision.sh:33`, after the add loop `:73-83` | refuse main's picker while the Chief of Staff pane is live, after the rows are written | `hooks/__tests__/ask-records-decision.test.sh` three cases (section 2, G6) |
| 351 | `218bd2b1` Cut 4 (host issue 3175) for answer-worker; asks 1, 3, 4 BUILD | PORT + BUILD | `scripts/answer-worker.sh:38`, `:54-70`, `:151-154`; `scripts/paths.sh:580-600`; `scripts/ask-main.sh:33-59` | open-question lookup; `--resume` reads the `--all` view; timeout tells main; interrupt route | `scripts/__tests__/ask-main.test.sh`, `scripts/__tests__/answer-worker.test.sh` (G7) |
| 352 | `218bd2b1` Cut 2 (host issue 3176) | PORT | `scripts/builder-codex-pass.sh` ~1250; `templates/_builder-brief-template.md:239`; `scripts/merge-unit-local.sh` end of step 1 ~234 | NARROWED GO line; marker only after a non-narrowed GO; one proof predicate before and after the rebase | `scripts/__tests__/builder-codex-pass-closing.test.sh`, `scripts/__tests__/merge-unit-local.test.sh` (G2) |
| 353 | `218bd2b1` Cut 2 (host issue 3177) | PORT | `scripts/main-watch.sh` `builder_watch` :325, `seat()` :973 and its finish/gate branch :1114-1121, finish post ~1140, the tick ~1466; `scripts/board.sh:199-235`; `templates/main-session.md` Details | report stamps (`due-*`), `report_send`, the `report_pending` fence, narrowed wording, report-first status | `scripts/__tests__/main-watch-report-wake.test.sh` (new), `scripts/__tests__/board.test.sh`, `scripts/__tests__/read-verdict.test.sh` (G2) |
| 354 | `218bd2b1` Cut 1 (host issue 3178) | PORT | `scripts/dashboard.sh:268-293` `merged()` | the newest reflog entry decides | `scripts/__tests__/dashboard-merged-unit.test.sh` (G1) |
| 355 | `218bd2b1` Cut 5 (host issue 3179) | PORT | `scripts/builder-codex-pass.sh` ~1236-1313; `scripts/builder-fresh-round.sh:106-141` | gate says why; round from the name; `fixer=` per round; atomic hand-off write | `scripts/__tests__/builder-fresh-round.test.sh`, `scripts/__tests__/builder-codex-pass-fresh-round.test.sh` (G3) |
| 356 | none | BUILD | `scripts/builder-codex-pass.sh:915-953` `rebase_and_test`, report header :1232 | time each pre-review step, one header line each | `scripts/__tests__/builder-codex-pass-rebase.test.sh` "a closing pass's report carries one timing line per pre-review step" |
| 357 | none | BUILD | `hooks/git-safety.sh:224-225` and a new `--record-add` mode; `hooks/hooks.json` PostToolUse Bash | allow a forced remove of a tmp worktree this session's add created, granted only after the add succeeded on an absent path | `hooks/__tests__/git-safety.test.sh` (G8) |
| 358 | none | BUILD | `skills/worktreereview/scripts/collect.py:486-497`, `:904`; `render.py:210-211` | count from the squash commit when the worktree is gone; "not recorded (<why>)" | `scripts/__tests__/worktreereview.test.sh` "a squash-merged unit's lines_changed comes from its squash commit" |
| 359 | `218bd2b1` (host issue 3183) | PORT | `scripts/seat.sh:412-414`; `templates/main-session.md` Details :55-64; `templates/_builder-brief-template.md`; `scripts/builder-codex-pass.sh` REST ~1038 | the five planning changes | `scripts/__tests__/builder-codex-pass.test.sh` "the review prompt places the plan's claims after the trace instruction"; `scripts/__tests__/brief-template.test.sh` (G5) |
| 360 | none | BUILD | `hooks/agent-startup-context.sh:104-145` (the Chief of Staff block); new `templates/cos-order.md`, new `scripts/cos-order-check.sh`; `docs/chief-of-staff.md` | five Chief of Staff rules and the order-file check | `scripts/__tests__/cos-order-check.test.sh` (new); `hooks/__tests__/agent-startup-context.test.sh` (G9) |
| 361 | `80e78119` | PORT | `scripts/builder-codex-pass.sh:897`, `:900`, `:907` | probe timeout 120 s, both messages | `scripts/__tests__/builder-codex-pass.test.sh` "a probe answering after 31 s passes" (G1) |
| 362 | `47632f56` (host issue 3184) | PORT | `scripts/builder-launch.sh:82-92`, `:146-162`; `scripts/builder-codex-pass.sh` pre-pass checks ~829-850, REPEAT :1263, REST ~1038, hand-off ~1260-1310 | Sites checked, first-return class stop, small plan stage, `Test:` lines, size line, `Break:` gate | `scripts/__tests__/builder-codex-pass-class-return.test.sh`, `scripts/__tests__/builder-launch-resume-from-plan.test.sh`, `scripts/__tests__/builder-codex-pass-decisions.test.sh` (G4) |
| 363 | `47632f56` send part (host issue 3186) | PIN only: the bug does not exist here | `scripts/to-main.sh:29`, `:41`; `scripts/cos-tell.sh:14`, `:20` | none: both helpers take positional words and build `--subject`/`--body` themselves | `scripts/__tests__/to-main.test.sh`, `scripts/__tests__/cos-tell.test.sh` "bare text after the type is refused with the usage line and no Orca call" |
| 364 | `b473949d` + `6be0003f` (part 1); part 2 BUILD | PORT + BUILD | new `hooks/cos-unfinished-stop.sh`; `hooks/hooks.json:99-105`; `scripts/dashboard_alerts.jq` ~56-75 | Stop hook; a pass-loop alert the alerts watcher already wakes on | `hooks/__tests__/cos-unfinished-stop.test.sh` (new); `scripts/__tests__/dashboard-alerts.test.sh` (G6, G9) |
| 365 | `bb280530` | PORT | `templates/global-rules.md:5`, `:89-91`; ponytail sites (section 2, G5), `scripts/worktree-setup.sh:73`, `:197`; `docs/configuration.md:48`, `:57` | remove the add-on, the rule and the option; worktree setup strips an earlier run's summary hook | `scripts/__tests__/install-lib-setup.test.sh`, `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/plugin-option.test.sh`, `scripts/__tests__/worktree-setup.test.sh` (G5) |

Host-only items of item 3 (no plugin issue): host issue 3173 (`218bd2b1` Cut 3, the diffstat before the first test
run) is PORTED in G6. Host issues 3167, 3169, 3170, 3171, 3172 and the original asks of host issue 3168 are DROPPED:
0.46.0 already ported them (section 4).

## 2. Groups and decisions

Every Decision names its test. Every new conditional write or safety check has a `Break:` line. The order for this
unit forbids red proofs, so no break is RUN in this unit: each `Break:` line is the target a reviewer checks by
reading (does the named test fail if the named condition is removed?). Assumption A1 covers this unit's own passes.
Every new flow step (a gate, a check, a delivery step or a merge step) has a `Catches:` line naming the one failure it
catches that no other step does. Section "Contracts" holds the `Produces:`/`Consumes:` lines across groups.

### G1 -- small ports: issues 361, 354, 363

- 361: `builder-codex-pass.sh:897` `timeout 30` -> `timeout 120`, the comment from the host commit; `:900` and
  `:907` say 120 s. Test: builder-codex-pass.test.sh "a probe answering after 31 s passes" (the `codex` stub sleeps
  31 s once: the one slow case, placed last in the file).
- 354: `merged()` (a) at `dashboard.sh:279-283`: the first-reflog comparison becomes the branch's NEWEST reflog entry
  (`git -C "$PP_MAIN" reflog show -1 --format=%gs "$ref"`); a subject starting `branch:` or `reset:` means live (the
  tip was placed there by `git worktree add` or `builder-launch.sh`'s reset, not made by the unit). The comment at
  :271-274 says so. Part (b), the finished-builds loop :285-290, is unchanged.
  Break: scripts/__tests__/dashboard-merged-unit.test.sh -- a worktree reset onto its plan commit in main stays in flight -- scripts/dashboard.sh:~282 the newest-entry branch:/reset: test
- 363: no code change. Evidence: `to-main.sh:29` refuses any call that is not exactly `<type> <subject> <body>`
  and `:41` builds `--subject "$2" --body "$3"` itself; `cos-tell.sh:14` does the same for `--note`, and its
  dictation path (:34-36) types text with `terminal send`, never `orchestration send`. `rg -n 'orchestration send'
  scripts hooks | grep '"\$@"'` is empty (2026-10-25). Two pin cases close the issue on a test.

Decision G1-1. Issue 363 closes on pins, not a refusal loop: the plugin has no `"$@"` forward to pin against.
Test: to-main.test.sh "bare text after the type is refused with the usage line and no Orca call".

### G2 -- the narrowed chain and report-first status: issues 352, 353 (host `218bd2b1` Cut 2)

- `builder-codex-pass.sh` ~1250: after a GO on a pass that ran as `review` while the closing pass is on (`CLOSING`
  is not `no`, :570-571), print `NARROWED GO: this GO merges nothing. Next: builder-codex-pass.sh <unit> <N+1> final;
  print your DONE line only after that pass's GO.`
- `_builder-brief-template.md:239`: the marker line follows only a GO the script did not mark `NARROWED GO`.
- `merge-unit-local.sh`: the step 3 proof (`generated_only` :245-255 and the `until` walk :256-261, which accepts a
  reviewed commit followed by a generated-only tail) becomes one function, `prove <step>`, that sets `PROVED`,
  `TAIL` and `BUILDER_PROOF` or calls `fail "<step>" ...`. It is called twice: at the end of step 1 (after `no_holds`
  :234, before `state rebase` :237) as `prove "step 1 proof"`, whose refusal adds "the branch is untouched", and at
  step 3 as today (the rebase can change the tip). The host's single `--verify` on the tip (`218bd2b1`) is not
  copied: it would refuse a supported generated-only tail before the walk runs. `generated_only`'s "not already on
  main" test (:249) holds before the rebase too.
  Catches: a narrowed-only or missing proof refused before the rebase rewrites the branch (step 3 alone catches it
  only after the branch was rewritten).
  Break: scripts/__tests__/merge-unit-local.test.sh -- narrowed-only proof: refused at step 1, branch HEAD unchanged -- scripts/merge-unit-local.sh:~235 the step 1 prove call
  Test: merge-unit-local.test.sh "a reviewed commit followed by a generated-only commit passes both proof steps and
  merges" (the generated-only tail case, run before and after the rebase).
- `main-watch.sh` (the host's durable retry contract, `218bd2b1`, ported whole; state lives in main-watch's state
  folder `$ST`, beside `item-*`):
  - `newest_round <wt> <unit>` (the newest `<u>-r<N>-reports.md`), `round_line <file>` (`<verdict> (<kind>)` for a
    file whose last non-empty line is a `VERDICT:` line, the kind from its `Pass:` line, :1232 writes it) and
    `report_key <unit> <file>` (`report-<u>-r<N>-<cksum of the file>`: a replacement build reusing the unit name is
    a new report).
  - `report_wake <wt> <unit>`, called by `builder_watch` (:325) right after the unit and handle are read, only
    STAMPS: for every finished round file, in N order, with no stamp and not delivered, it writes
    `$ST/due-<key>` (four lines: unit, round, subject, body) through `$ST/.due-tmp` and `mv` (the temp name is
    outside the `due-*` glob, so a half stamp is never read). Next steps in the body: GO `final` "merge"; GO
    `review` "narrowed -- needs a final pass: builder-codex-pass.sh <u> <N+1> final"; GO `adversarial` "a
    first-pass GO"; NO-GO "fix round <N> runs from <u>-fix-r<N>.md"; no `Pass:` line "pass kind not recorded". A
    failed stamp write is noted in the tick's diagnostic (`note`) and written again next tick.
  - `delivered <item file>`: the item holds `handled`, `close=1` or `posted=<n>` (`post()` :205 writes `posted=`
    only when Orca took the send).
  - `report_send`, called once per tick before `merge_start` (~1466): every stamp, by unit then round, from the
    STAMP's own text (the worktree, seat record and round file may all be gone): a delivered stamp is removed; a
    stamp with an earlier report of its unit pending waits; otherwise `post "<key>" "" <subject> <body> once`. An
    unsent item whose task is not in this run's task list is made again.
  - `report_pending <unit> [<round>]`: true when a finished report of the unit (below `<round>` when given) has not
    reached main: it reads the worktree's finished round files against `delivered`, then any stamp still waiting
    (for a removed worktree). Fails closed: a step that failed before its stamp exists still holds.
  - The fence, in `seat()` before the finished branch (:1114) that posts the finish and calls `gate` (:1121, the
    auto-merge): `[ "$4" = builder ] && report_pending "$u" && return 0`. Nothing ends or merges a Builder unit
    while one of its reports has not reached main.
  Catches: report_wake catches a finished report main was never told of; report_send catches a send that failed
  after its worktree was removed; the fence catches a finish or merge that would remove the worktree before an
  earlier report reached main.
  Break: scripts/__tests__/main-watch-report-wake.test.sh -- every completed report wakes main once, whichever order they land in -- scripts/main-watch.sh report_send the per-key once check
  Break: scripts/__tests__/main-watch-report-wake.test.sh -- r1's send fails, the worktree is removed, the next tick posts r1 from its stamp -- scripts/main-watch.sh report_send the stamp-only post
  Break: scripts/__tests__/main-watch-report-wake.test.sh -- a finished Builder with an undelivered report is neither posted finished nor merged -- scripts/main-watch.sh seat() the report_pending fence
- The stopped post (~1140): when the newest report is a narrowed GO, the text is `finished on a narrowed pass; needs
  a final pass: builder-codex-pass.sh <u> <N+1> final`, not "stopped with no marker". A Builder's finish post leads
  with `Newest report: <file>: <verdict> (<kind>)`.
- `board.sh` stopped-panes loop (:199-235): a Builder seat whose worktree has a round file prints its verdict, kind
  and age instead of read-verdict's last words; read-verdict only when there is none.
- `templates/main-session.md` Details: a Builder's state is read from its newest report, not its pane.
- Issue 353 ask 1 holds already: `main-watch.sh:1043-1051` reads DONE as the last line of the latest message and
  `read-verdict.sh:107`, `:117`, `:161` set `marker` from the last line. A pin case documents it.

Decision G2-1. The pass script says the next command; it does not run the final pass itself (host Decision 7: one
call would run two passes with no Builder turn between). Test: builder-codex-pass-closing.test.sh "a narrowed GO
with the closing pass on prints NARROWED GO and the final command".
Decision G2-2. "Refuse the done marker" is a brief line plus main-watch's narrowed wording, not a new Stop hook (host
Decision 8). Test: main-watch-report-wake.test.sh "a DONE after a narrowed GO is posted as finished on a narrowed
pass, needing a final pass".
Decision G2-3. The first tick after the merge wakes main once per completed report of each live Builder; there is no
record of what was seen before (host Decision 20). Test: main-watch-report-wake.test.sh "a second tick posts
nothing".
Decision G2-4. Issue 353 ask 1 is pinned, not rebuilt. Test: read-verdict.test.sh "a marker alone on the last line
after a VERDICT line reads marker=1".
Decision G2-5. Report delivery is the host's stamp contract, not a rescan of round files: `post()` keeps only the
task and `posted=` state (:205-247), not the body, so a rescan cannot retry a report whose worktree the merge
removed. One retry path (`report_send`), one question for fence and order (`report_pending`). Test:
main-watch-report-wake.test.sh "r1's send fails, the worktree is removed, the next tick posts r1 from its stamp".
Decision G2-6. Proof before and after the rebase is one predicate, so the generated-only tail rule
(`merge-unit-local.sh:240-247`) holds at both steps. Test: merge-unit-local.test.sh "a reviewed commit followed by a
generated-only commit passes both proof steps and merges".

### G3 -- the fix hand-off: issue 355 (host `218bd2b1` Cut 5, the host issue 3179 part)

- (a) `builder-codex-pass.sh` fix hand-off preconditions (~1236-1262): each failed check prints `NO FIX HAND-OFF after
  pass <N>: <check> (<value>); this session fixes on its launch model`. When `$PP_SCRATCH/seat-<unit>-builder.txt`
  exists, the same line goes to main with `to-main.sh question`, with "re-run the pass from the Builder's pane to
  hand off". Exit 0.
- (b) `builder-fresh-round.sh:113`: the count `K` goes; the round is the N of `fix-r<N>` (already matched at :112).
  N = 1 takes `fixer first` (:126), N > 1 takes `fixer` (:127). The comment at :106-111 says the name, not a count.
- (c) after `/effort` (:139-141): `fixer=<rule> model=<m> effort=<e> round=<N>` appended to the seat record (today
  `fixer=$RULE` only, :141).
- (d) the hand-off writer (:1260 to the helper start :1313): writes to `$HAND.tmp`, then `[ ! -d "$HAND" ]` and
  `mv -f`; the script's EXIT handler removes `$HAND.tmp` on a non-zero exit, prints `NO FIX HAND-OFF after pass <N>:
  writing <HAND> failed (exit <rc>)` and tells main as in (a). The helper never starts on a failed write.
  Break: scripts/__tests__/builder-codex-pass-fresh-round.test.sh -- a hand-off write that fails leaves no file at the hand-off path and starts no helper -- scripts/builder-codex-pass.sh:~1312 the mv-after-check publish
  Catches: (a) catches a fix hand-off skipped in silence; (d) catches a half-written hand-off a fresh fixer would
  start from.

Decision G3-1. Port the host's resolution, not the issue's first ask: no `/model` switch in place after a NO-GO and
none on a plain `<unit>-handoff.md` (host Decisions 3 and 14: a model switch belongs at a cleared context, because
the prompt cache is per model). In-session fixing is made visible instead: (a) tells main and names the re-run that
hands off. The CHANGELOG says which two asks are not built and why. Test: builder-fresh-round.test.sh "a plain
hand-off types no /model".
Decision G3-2. The round is the number in the name; a lone `fix-r7` is a later round (host Decision 18). Test:
builder-fresh-round.test.sh "a lone fix-r7 runs on the later-round fixer".
Decision G3-3. The gate exits 0 after saying why: the pass itself succeeded (host Decision 13). Test:
builder-codex-pass-fresh-round.test.sh "a skipped hand-off says which check failed and tells main when a Builder
seat exists".

### G4 -- the build loop: issue 362 (host `47632f56`), the host issue 3168 widening (host `218bd2b1` Cut 5)

- Launch, `builder-launch.sh`. The Data design awk (:82-92) becomes `has_section <heading>`; a second refusal: neither
  the batch nor the plan has `## What can go wrong` with a line under it. A new plan-facts awk reads
  `^[-*] Planned size: ~?[0-9]+ files?, ~?[0-9]+ (changed )?lines?` with any trailing text, and prints `untested
  <first 60 chars>` for each top-level item under `## Decisions` or `## Accepted failure modes` with no `Test:` before
  the next item or heading; the refusal lists them. `--from-plan` NO-GO branch (:146-162): a judged NO-GO plan launches
  when it is under 150 planned lines (`SMALL_PLAN=150` beside the check) and `$PP_MAIN/.claude/briefs/<unit>-main-rulings.md`
  is newer than the judge's seat record; the Builder writes each ruling into the plan with a change-log line before
  pass 1.
  Break: scripts/__tests__/builder-launch-resume-from-plan.test.sh -- a small NO-GO plan launches with main's newer rulings, and is refused without them -- scripts/builder-launch.sh:~150 the rulings-newer-than-judge test
  Break: scripts/__tests__/builder-launch-resume-from-plan.test.sh -- a decision with no Test: is refused, naming it -- scripts/builder-launch.sh plan-facts awk the untested print
  Break: scripts/__tests__/builder-launch-resume-from-plan.test.sh -- a plan with no What can go wrong section is refused -- scripts/builder-launch.sh has_section's second call
  Catches: the What can go wrong refusal catches a plan whose failure cases no reviewer can check; the plan-facts awk
  catches a decision with no test and a plan with no size line; the small-plan NO-GO branch catches a judged NO-GO
  plan launched without main's rulings.
- Launch fixtures (Decision G4-3, no compatibility path, no time-limit raise): the shared fixture's `batchfor`
  (`scripts/__tests__/fixtures/builder-launch-resume-setup.sh:32`) gains `## What can go wrong` with one row, and its
  toy plan gains a `- Planned size:` line, so every caller (`builder-launch-resume.test.sh`,
  `builder-launch-resume-launch-line.test.sh`, `builder-launch-resume-rollback.test.sh`,
  `builder-launch-resume-from-plan.test.sh`) launches as before. In `builder-launch-resume-launch-line.test.sh`, the
  0.46.0 cases that expect a batch with no Data design heading to open its Builder (`dd u15`, :33-37, and the brief
  line it checks) become refusals: "a batch with no Data design section is refused" (`2:1`, the REFUSED line). The
  `dd` helper's sed (:26) keeps the What can go wrong section it does not delete. Test: those two files green, run
  `bash scripts/run-shell-tests.sh scripts/__tests__/builder-launch-resume-launch-line.test.sh
  scripts/__tests__/builder-launch-resume-rollback.test.sh` in the background.
- Pass, `builder-codex-pass.sh`. Pre-pass checks (~829-850): when the last round before N ended NO-GO, refuse unless
  the evidence has `## Sites checked (pass M)` with a `Search: <command>` line and at least one `- <path>:<line> fixed`
  or `- <path>:<line> not affected, <why>` line; when KIND is adversarial, refuse unless every plan `Break:` line has a
  `Mutation-verified:` line holding its `<test file> -- <check label>` and `RED`. REPEAT (:1263) takes the union of
  `read-verdict.sh --repeat-class` over EVERY earlier round file, not the previous one (`read-verdict.sh:388-391`
  compares two). REST (~1038) gains the Sites list ("a site of the pattern missing from it, or wrongly marked not
  affected, is a finding") and the plan's `## What can go wrong` beside Stated limits (:1027): a finding outside it
  ends `(not in the plan list)`. The fix hand-off gains two bullets: write `Sites checked`; add a missed case, with its
  test, to the plan's section in the same commit.
  Break: scripts/__tests__/builder-codex-pass-class-return.test.sh -- after a NO-GO the next pass refuses without Sites checked -- scripts/builder-codex-pass.sh:~840 the Sites checked refusal
  Break: scripts/__tests__/builder-codex-pass-class-return.test.sh -- a class's first return after a GO round is a class stop -- scripts/builder-codex-pass.sh:~1263 the every-earlier-round union
  Break: scripts/__tests__/builder-codex-pass-decisions.test.sh -- pass 1 refuses a Break: line with no RED Mutation-verified line -- scripts/builder-codex-pass.sh:~845 the Break gate
  Catches: the Sites checked refusal catches a fix that mended one site of a pattern and not its siblings; the Break
  gate catches a safety check whose test does not fail when the check is removed; the every-round class union
  catches a class that returns after a GO round, which the two-round compare misses.
- Templates: `_builder-brief-template.md` (Sites checked after a NO-GO; the break run before pass 1, scope: new
  security checks and conditional writes only); `seat.sh:412-414` plan-author lines (`- Planned size:` line, a `Test:`
  per decision, a `Break:` per new conditional write or safety check, the What can go wrong section).

Decision G4-1. Sites checked is required after every NO-GO, from the first (host Decision 1). Test:
builder-codex-pass-class-return.test.sh "after a NO-GO the next pass refuses without Sites checked".
Decision G4-2. The plugin has no "risky file forces Panel" rule to supersede: `plan-tier.sh:22-29` picks Panel only
from keyword triggers (`config/plan-triggers.tsv`). The small-plan change ports as the NO-GO acceptance above (host
Decision 5); the Panel triggers stay. Test: builder-launch-resume-from-plan.test.sh "a NO-GO plan at 150 planned lines
is refused, at 149 taken".
Decision G4-3. No compatibility branch for plans or batches written before 0.47.0: a missing `Test:` line, size line
or What can go wrong section is refused, the message naming the fix. This follows the host (2026-10-25, the newer
rule) and `templates/global-rules.md:6` (ask before building compatibility; the count here is the plans in flight at
upgrade, usually 0 or 1). The same rule removes the 0.46.0 Data design exception (`builder-launch.sh:90-91`: a batch
with no Data design heading opens and the brief moves the answer to the Builder): a missing heading is refused like
an empty one, and the NOTE and its brief line go. Test: builder-launch-resume-from-plan.test.sh "a batch with no What
can go wrong section is refused"; builder-launch-resume-launch-line.test.sh "a batch with no Data design section is
refused".
Decision G4-4. The host's two approved additions in `47632f56` do not apply: the typecheck Stop-hook skip and the
bugfix-lock message have no plugin site (`hooks/` holds no `typecheck.sh` and no `bugfix-test-lock.sh`, `git ls-files
hooks`, 2026-10-25). Test: none, no site.
Decision G4-5. The class stop compares round N with every earlier round, GO rounds included (host Decision 2). Test:
builder-codex-pass-class-return.test.sh "a class's first return after a GO round is a class stop".

### G5 -- planning text and the ponytail removal: issues 359, 365 (host `218bd2b1` 3183 part, `bb280530`)

- 359, 1-3: `seat.sh:412-414` plan-author lines and `templates/main-session.md` Details (:55-64, where main writes the
  plan specs): a What can go wrong table (case / input or starting state / expected result / test name; at most five;
  "checked, none" when empty; each row's test in the acceptance tests); every `[likely]`/`[uncertain]` claim settled
  (command + output) or a Builder check before the dependent cut, with the action per outcome; each cut lists Produces
  and Consumes and every existing consumer of a contract it changes.
- 359, 4: accepted judge findings are written into the plan before the Builder starts, one `## Plan change log` line
  each; the judge rechecks only what changed. `_builder-brief-template.md`: before the first edit, one table of cut
  pairs sharing a file or symbol; a finding whose root cause is the plan amends the plan first, then the code.
- 359, 5: main's judge-spec lines (Details :61-63): read the plan as a Builder who cannot ask and list every place a
  wrong guess would change the code; try to falsify each checkable claim. `builder-codex-pass.sh` REST (~1038): the
  plan's claims and accepted choices (`## Claims to falsify`, Decisions) come AFTER the trace instruction, as claims to
  falsify.
- 365: delete `templates/global-rules.md:5` and the last sentence of `:89-91`; `templates/ponytail/` (3 files, 91
  lines); the `ponytail` option (`.claude-plugin/plugin.json:226-232`, `scripts/paths.sh:1137`, `:1156`); its entry in
  `config/addons.tsv:6`; `scripts/builder-launch.sh:252-255` and `templates/_builder-brief-template.md:26`
  (`{ponytail}`); `scripts/setup.sh` (:12, :36, :119, :212, :351-361, :383, :393, :464-470, :475-477, :482, :505,
  :625-627, and `--ponytail` in `TAKES` :55); `scripts/install-lib.sh:493-499` (main's lean list drops the ponytail
  key); `skills/setup/SKILL.md:192-197` (question 11; later questions renumbered); `skills/uninstall/SKILL.md:18`;
  `hooks/dependency-addition-guard.sh:3`, `:42`, `:278` (the "Rule 2 / ponytail" wording, as the host commit drops
  it); docs `add-ons.md`, `commands.md:38-41`, `setup-questions.md:23`, `worker-panes.md:11-12`, `:17`, `:32`,
  `uninstall.md:27`, `configuration.md:48` (main's lean list names "the ponytail rules and skill") and `:57` (the
  `ponytail` project key).
- 365, the worktree-setup caller (host `bb280530` changes its twin): `scripts/worktree-setup.sh` reads the removed
  folder at :73 (`SUMMARY=$(cd .../templates/ponytail && pwd)/SUMMARY.md`, which exits the script under `set -e`
  once the folder is gone) and the removed option at :197 (`LEVEL=$(... pp_option ponytail)`). Both go, with `PONY`
  (:198-199), the `--argjson pony`/`--arg sum` inputs (:200) and the add branch at :224 that sets
  `ponytail@ponytail` off and registers the summary hook. The summary-hook cleanup stays and becomes the only
  ponytail logic: the filter at :78 and the `$sumhook` block at :207-209 match the old command by its
  `/templates/ponytail/SUMMARY[.]md"$` tail, so a rerun on a worktree set up before 0.47.0 drops that hook command
  (an owner hook in the same registration stays) and the off leaf the run wrote beside it. The lean-pane report line
  (:227) drops its ponytail part; the comments at :21, :72, :97-98 and :186-194 lose the summary wording.
  Catches: a worktree whose SessionStart hook would `cat` a deleted file on every start.
  Break: scripts/__tests__/worktree-setup.test.sh -- a rerun on a worktree set up with the summary hook drops that hook and its off leaf and keeps an owner hook beside it -- scripts/worktree-setup.sh:~207 the $sumhook test
- 365, option tests: `scripts/__tests__/plugin-option.test.sh` (22 ponytail lines) uses `ponytail` two ways. As its
  "level" example (:6 comment, :25, :32, :38-39, :42, :49-52) it tests the removed option's own validation branch
  (`paths.sh:1156`): those cases go with the branch; the picker (`builderEffort`) and number (`dashboardPort`) cases
  still cover each source. :28 ("another plugin's options are never read") moves to `builderEffort` (the fixture's
  `other@elsewhere` already carries `builderEffort: "max"`). In the pre-fill cases (:201-242) `ponytail` is only a key
  name: it becomes `promptCacheTtl` (`"leave"`), with the expected JSON adjusted. The fixture's `other@elsewhere`
  options keep their `ponytail: true` (another plugin's key, never read). Test: `bash scripts/run-shell-tests.sh
  scripts/__tests__/plugin-option.test.sh` green (in the background).
- Existing installs (the owner's ruling: count first). `config/retired.tsv` is a lint list only (its reader is
  `scripts/instruction-lint.py:80`, which prints diagnostics at :207); it migrates nothing. The `--no-ponytail` row's
  replacement column becomes "nothing: the add-on is removed" and one row lints `--ponytail` the same way, so no
  instruction file advertises the removed flag. How many installs carry a saved `ponytail` answer: on this machine 0
  (no `~/.commandeck/install/`, no `ponytail` key in any project `commandeck.json` or in the plugin's
  `pluginConfigs` in `~/.claude/settings.json`, checked 2026-10-25); elsewhere unknowable (a public plugin with no
  install registry). So this unit plans NO cleanup of an existing install: no removal of an installed ponytail skill
  copy and no saved-option rewrite (section "Question for Max"). A saved `ponytail` answer left in a project file is
  read by nothing after G5.
- Tests that assert ponytail (`rg -c -i ponytail scripts/__tests__ hooks/__tests__`: install-lib-setup 13,
  profile-revoke 13, profile-settings 11, plugin 6, plugin-option 4, update 2, dependency-addition-guard 1,
  worktree-setup 53) change only where they assert the removed behaviour; a fixture that merely names the
  third-party plugin in `enabledPlugins` stays.

Decision G5-1. Old `ponytail:` comment tags stay (issue 365, not in scope). Test: none, out of scope by the issue.
Decision G5-2. No cleanup of existing installs in this unit: the count of installs carrying a saved `ponytail` answer
is unknowable beyond this machine's 0, so per the owner's ruling none is planned and the owner is asked.
`config/retired.tsv` gains a lint row only. Test: `scripts/__tests__/rules-audit.test.sh` "a retired --ponytail in a
template is flagged with what replaced it" (beside its `--no-ponytail` case, :20-22).
Decision G5-3. Issue 359 item 5c is one ordering change in REST, no new section reader. Test: builder-codex-pass.test.sh
"the review prompt places the plan's claims after the trace instruction".

### G6 -- hooks: issue 350, host issue 3173, issue 364 part 1

- 350 (host Cut 3): `ask-records-decision.sh` after the add loop (:73-83): when every row was added and
  `cos-tell.sh --handle` exits 0, exit 2 with: recorded as `<ids>`; the Chief of Staff puts it to the owner and
  relay-order.sh sends the answer; do not open a picker. Any other result opens the picker (fail open). The comment
  at :33 says the guard runs after recording.
  Break: hooks/__tests__/ask-records-decision.test.sh -- main with a live Chief of Staff pane: refused with the redirect, row written -- hooks/ask-records-decision.sh:~84 the cos-tell --handle check
  Catches: a question main puts to a picker the owner is not watching while the Chief of Staff relays.
- 3173 (host Cut 3): `suite-rerun-guard.sh`, before its final pending write: in a linked worktree, not a reviewer,
  with a `session_id`, on the session's first test run (`SUITE_RE` :150), print one `additionalContext` block:
  `git diff --stat $(git merge-base main HEAD)`, the untracked files (20 named, then a count), "compare with the files
  your brief names". Marker `diffstat-<session_id>` in the guard's state folder, created with `set -C` (one of two
  concurrent calls creates it). Exit code unchanged.
  Break: hooks/__tests__/suite-rerun-guard.test.sh -- two first suite runs released at once in one session print the diffstat exactly once -- hooks/suite-rerun-guard.sh the noclobber create
  Catches: a worktree carrying files outside its brief, seen before the first test run rather than at review.
- 364 part 1 (host `b473949d`, `6be0003f`): new `hooks/cos-unfinished-stop.sh`, registered in `hooks/hooks.json`
  Stop (:99-105), arming the hook-fire log. Runs in the Chief-of-Staff worktree, and in the main checkout when
  `cos-tell.sh --handle` fails (no Chief of Staff, the issue's "and main when no Chief of Staff runs", BUILT). The
  host's pattern list with the host's names replaced by "main". The second Stop of a turn passes.
  Break: hooks/__tests__/cos-unfinished-stop.test.sh -- an unfinished-work reply is blocked once -- hooks/cos-unfinished-stop.sh the HIT test
  Catches: a Chief of Staff (or main with none) ending its turn on "I'll do X" with X not done.

Decision G6-1. The picker is refused after recording (host Decision 6): the recorded row is how the owner sees it.
Test: ask-records-decision.test.sh "main with no Chief of Staff pane: picker allowed".
Decision G6-2. Host issue 3173 lives in the suite-rerun guard, which already sees test runs; it advises, never blocks
(host Decision 5). Test: suite-rerun-guard.test.sh "main checkout and a reviewer pane print nothing".
Decision G6-3. The hook count rises by one (`scripts/__tests__/plugin.test.sh`), `docs/hooks.md` gains one row. Test:
plugin.test.sh, its hook-count case.

### G7 -- answers: issue 351 (host `218bd2b1` Cut 4 for answer-worker; asks 1, 3, 4 BUILT)

- Port: `paths.sh` pp_task_close's id gathering (near `pp_open_ask`, :580-600) moves into `pp_seat_open_ask <handle>
  <record>`; `answer-worker.sh`, after the handle is resolved and only with no question id (:38): the seat record
  whose `handle=` is the pane; 0 -> `QID` is the open question and the reply goes in its thread; 1 -> as today;
  2 -> says the open question could not be read and goes on.
- Ask 1 (BUILD): `ask-main.sh --resume` (:33-59), before it waits again, reads `orchestration check --terminal "$H"
  --all --json` and takes a message in the question's thread (the same match :44-52 uses) as the answer.
- Ask 2: the background follower (`answer-worker.sh:157-170`) also follows the "queued, not read yet" path (:151-154)
  until the reply is acknowledged (A2 names the field), and tells main when it is not after the wait.
- Ask 3 (BUILD): when `ask-main.sh` passes its deadline it sends main `to-main.sh question "ask-main: <id> unanswered"`
  once, so main can tell a lost answer from none.
- Ask 4 (BUILD): `answer-worker.sh --interrupt`: for a pane with an open `ask-main.sh` state file (:31, deadline not
  passed), the answer goes with `orca-ide terminal send --interrupt` (the flag exists: `orca-ide terminal send --help`,
  2026-10-25). The hooks see only `bash answer-worker.sh ...`, so `duplicate-agent-guard.sh` does not refuse it.
  Break: scripts/__tests__/answer-worker.test.sh -- --interrupt to a pane with no open ask-main question is refused -- scripts/answer-worker.sh the open-state check
  Catches: an interrupt typed into a pane that is mid-turn on other work, not waiting on main.

Decision G7-1. One helper both callers use, so the answer and the task close count the same questions (host Decision
11). Test: answer-worker.test.sh "no id given, the pane has an open question sent under its dispatch: the answer is a
reply in that thread".
Decision G7-2. The interrupt is opt-in (`--interrupt`), never automatic. Test: answer-worker.test.sh "without
--interrupt nothing is typed into a mid-turn pane".

### G8 -- issues 356, 357, 358

- 356: `rebase_and_test` (:915-953) and the closing pass's precheck time each step with `SECONDS`; the report header
  (:1232, beside `Timing:`) gains `Pre-review: rebase <s> s, tests <s> s, precheck <s> s` (a step not run says
  `not run`).
- 357: `git-safety.sh`. Ownership is granted only after a successful add on a path that was absent before it:
  - PreToolUse (today's Bash registration): a `git worktree add <path>` whose path resolves under
    `${TMPDIR:-/tmp}`, `/tmp` or `/private/tmp` and does NOT exist yet appends `pending\t<session_id>\t<realpath of
    the parent>/<name>` to `$PP_SCRATCH/tmp-worktrees`. A path that exists (another session's worktree, a file,
    anything) records nothing.
  - PostToolUse Bash (new registration in `hooks/hooks.json` PostToolUse, `git-safety.sh --record-add`; Claude Code
    fires PostToolUse only for a call that exited 0, a failed one fires PostToolUseFailure, :5): for the same
    command, when this session has a `pending` line for the path and `git -C <path> rev-parse --git-common-dir` now
    succeeds, it appends `owned\t<session_id>\t<path>`. A command that exits 0 after a failed add (`git worktree add
    /tmp/x HEAD; true`) grants nothing: the path was present before (no pending line) or is not a worktree after.
  - At :224-225 a forced remove is allowed only when an `owned` line of the same session names that path and it is
    under tmp; every other forced remove is blocked as today. No `session_id` (a Codex pane): nothing recorded,
    blocked as today.
  Catches: a forced remove of a tmp worktree another session owns, whose path this session's failed add named.
  Break: hooks/__tests__/git-safety.test.sh -- forced removal of a worktree the session did not create stays blocked -- hooks/git-safety.sh:~224 the owned-line test
  Break: hooks/__tests__/git-safety.test.sh -- a failed add on a path another session's worktree holds grants no removal -- hooks/git-safety.sh the PreToolUse absent-path test
- 358: `collect.py` `lines_changed()` (:486-497) returns None when the worktree is gone, and the merge's step 5
  removes it (`merge-unit-local.sh:160`), so a squash-merged unit gets no count. When the worktree is gone, count the
  unit's squash commit on main (`git show --numstat --format= <sha> -- . ':(exclude).claude/briefs'`), its sha from
  the finished-builds record (A5). `render.py:210-211`: None prints `Lines changed: not recorded (<why>)`.

Decision G8-1. Ownership needs both proofs: the path was absent before the add (PreToolUse `pending`) and the call
succeeded with a worktree at the path (PostToolUse `owned`). Either alone is not enough: a PreToolUse record alone
grants a failed add on another session's path; a PostToolUse check alone grants `git worktree add <foreign path>;
true`. Tests: git-safety.test.sh "removing a tmp worktree this session added is allowed"; "session B's failed add on
session A's worktree path, then B's forced remove: blocked, A's worktree and its uncommitted file still there" (a
real worktree under a test tmp dir, A's `owned` line written by the hook itself); "a failed add followed by `; true`
grants nothing"; "a pending line with no PostToolUse (the add failed) grants nothing".

### G9 -- issue 360, issue 364 part 2

- 364 part 2 (BUILD): `dashboard_alerts.jq` (~56-75) raises `pass-loop-<unit>-r<N>` when a live unit's newest pass is
  4 or more and NO-GO, with its top findings. `cos-watch-alerts.sh` already wakes the Chief of Staff once per new alert
  id (its seen file); with no Chief of Staff, main hears every finished report through G2's report wake.
  Break: scripts/__tests__/dashboard-alerts.test.sh -- a pass-4 NO-GO raises pass-loop once and a GO raises none -- scripts/dashboard_alerts.jq the pass-loop select
  Catches: a unit looping on review rounds with nobody told while each pass still posts its own report.
- 360 (BUILD): the Chief of Staff block in `hooks/agent-startup-context.sh` (:104-145) gains the five rules (scope is
  the owner's words; additions under `## Chief of Staff additions -- NOT ordered`; one multi-select prompt, decoy
  first; no bundle approvals; at a pass-loop alert for pass 5 or more, or a class stop, tell the owner which part of
  the scope produces the findings and whether the owner's words asked for it). New `templates/cos-order.md` (two
  headings); new `scripts/cos-order-check.sh <file>` flags a file whose first section is not `## The owner's words`, or
  with additions outside the NOT-ordered heading; the rule says run it before sending an order file to main.
  `docs/chief-of-staff.md` gains a short section.
  Break: scripts/__tests__/cos-order-check.test.sh -- an order with an addition outside the NOT-ordered section is flagged -- scripts/cos-order-check.sh the section test
  Catches: a Chief of Staff addition passed to main as if it were the owner's words.

Decision G9-1. The pass watcher is a dashboard alert, not a fifth watcher: the alerts watcher and its seen file
already give "once per unit and pass", and the Chief of Staff Stop hook (`hooks/cos-inbox-waiter-stop.sh`) needs no
new name. Test: dashboard-alerts.test.sh "a pass-4 NO-GO raises pass-loop once and a GO raises none".
Decision G9-2. The plugin's relay has no order file today (`relay-order.sh` sends the owner's words verbatim); the
order file is written only when the Chief of Staff adds anything. Test: cos-order-check.test.sh "an order file
without the owner's-words section is flagged".

### G10 -- the units mod: issue 349 (host `c7aaf716`, then `84118aa9`: the v2 layout, the stall mechanic removed)

The owner approved the second layout and ordered the whole stall mechanic removed (issue 349's comments of
2026-10-25, re-read: no stall mark, no stall toast, no `stallMinutes` option; show only what is known, never an empty
or unknown field). The port is the host mod as `84118aa9` leaves it (`.claude/units-mod`: hooks, tests, manifest,
README, tsconfig), adapted to the plugin site:
- `hooks/sources.ts` -> `hooks/units-sources.ts` (364 lines), `hooks/units.tsx` (299), `hooks/units.test.tsx` (361),
  `hooks/sources.test.tsx` -> `hooks/units-sources.test.tsx` (103); each under the 400-line cap
  (`hooks/file-size-cop.sh`). `hooks/hooks.json:2` modules gains `./units.tsx`.
- Manifest: the host mod's three options become `unitsBand`, `unitsPane`, `unitsStatus` in `.claude-plugin/plugin.json`
  (`auto|on|off`; `auto` is on in main and the Chief of Staff and off in worker and reviewer panes; the status
  option's description says "a verdict or a merge"). No stall option. `/units` and `/units <view> on|off`.
  `types/index.d.ts` gains the atom shapes.
- README -> a units section in `docs/dashboard.md` (the host README's text without the stall lines, its paths made
  the plugin's). tsconfig: the host mod's one-line `tsconfig.json` (extends `./.claude-plugin/types/tsconfig.json`) is
  already the plugin root's `tsconfig.json`, which covers `hooks/` (`hooks/autodecide.tsx` builds under it); nothing
  to add.
- Adapted, not redesigned: the snapshot is `$HOME/.commandeck/dashboard/data.js` (`dashboard.sh:4`); merge rows read
  the plugin's merge logs (A4); the host's push-chain lanes and long-job locks are dropped (the plugin has neither).
- No stall producer: the v2 parser reads no `fileAgeSec` (`84118aa9` removed it), so `dashboard.sh` gains no field
  for it.
- Merge gate (the host's change): `merge-unit-local.sh`'s touched-tests step runs `claude plugin test . && claude
  plugin validate .` in the worktree when a path under `hooks/*.ts`, `hooks/*.tsx` or `types/` changed.
  Catches: a mod change that breaks the mod's own tests or the manifest, which the shell suites never load.
  Break: scripts/__tests__/merge-unit-local.test.sh -- a changed hooks module runs claude plugin test -- scripts/merge-unit-local.sh the changed-path test

Decision G10-1. The mod reads the dashboard snapshot, which already parses the event logs and round files
(`dashboard.sh` ~458), so "stage parsing from a sample event log and round file" is tested at the snapshot. Before the
port, the Builder records in the evidence file which of the v2 parser's fields the plugin snapshot holds
(`units.inFlight[].stage`, `.round`, `.ageSec`, `.agents`, `.builder.verdict`, `.verdictRound`, `.findings`,
`.cost.stages`, `.issues`, `.built`, `.startedAt`; `units.finishedBuilds[].cost.total.usd`;
`units.mergedSincePush[].mergedAt`). A missing one renders nothing (the layout shows only what is known) and is a
follow-up, never a guess or a new producer in this unit. Test: units-sources.test.tsx "a snapshot parses its units,
verdict and costs".
Decision G10-3. No stall mechanic anywhere: no option, no mark, no toast, no producer. Test: units.test.tsx "a unit
with an old worktree shows no stall mark and raises no toast" (a case added beside the ported ones).
Decision G10-2. With no live units every view draws nothing. Test: units.test.tsx "no live units: no band row, no
pane, no status line".

### G11 -- releases: issue 348

- `scripts/release-notes.sh <version>`: prints that version's CHANGELOG section, the text `update.sh:27` prints for the
  newest (`update.sh` calls it). Exit 1 with a message when the section is missing.
- `scripts/release-decide.sh <before sha> <after sha>`: the one decision path. Prints `release v<version>` when
  `.claude-plugin/plugin.json`'s version at `<after>` differs from `<before>`'s and tag `v<version>` does not exist;
  otherwise `skip: <why>` (version unchanged, tag exists). Exit 0 either way; exit 1 when a version cannot be read.
- `.github/workflows/release.yml`, on push to `main` (`contents: write`, its own job; `ci.yml` keeps `contents:
  read`): its first step runs `bash scripts/release-decide.sh "${{ github.event.before }}" "$GITHUB_SHA"`, and every
  later step runs only when that output starts `release ` (a step output, `if:`). It then tags `v<version>` and
  publishes the release with `release-notes.sh`'s notes; a release that exists already changes nothing; a missing
  section fails the job. The workflow holds no version comparison of its own.
  Catches: a push that would tag or publish a version already released, or one whose version did not change.
  Break: scripts/__tests__/release-notes.test.sh -- an unchanged version decides skip -- scripts/release-decide.sh the version compare
  Break: scripts/__tests__/release-notes.test.sh -- the release workflow gates every tag and publish step on release-decide's output -- .github/workflows/release.yml the if: on each later step (a text check of the workflow: the decide step exists and every later step names its output)
- `scripts/release-backfill.sh [--plan]`: for each version, oldest first, the commit that set it in `plugin.json`
  (`git log -S`), tag and release unless they exist (the tag test is `release-decide.sh`'s). `--plan` prints and does
  nothing.

Decision G11-1. Nothing is tagged or published in this unit: the merge is local, and the workflow runs only on a
push. The backfill creates public tags and releases, so it is run by main after the push, on the owner's go. Test:
release-notes.test.sh "backfill --plan lists every version oldest first and creates nothing".

## 3. Assumptions (each settled, or a Builder check with the action per outcome)

- Settled: 0.46.0 holds the host twins dropped in section 4 (CHANGELOG.md 0.46.0 entry; code cited there).
- Settled: the worktree is removed at merge step 5 (`merge-unit-local.sh:160`) and `lines_changed` returns None then
  (`collect.py:487-497`, its docstring).
- Settled: `orca-ide terminal send` takes `--interrupt`; `orca-ide orchestration check` takes `--all` (both `--help`,
  2026-10-25).
- Settled: no plugin helper forwards `"$@"` to `orchestration send` (G1, command and output above).
- A1, settled (main's ruling): this unit's own passes run the pass script from plugin main's checkout, never the
  worktree's copy, so the Break gate this unit adds takes effect from the next unit. The command, run from this
  worktree: `bash "$(git rev-parse --path-format=absolute --git-common-dir | sed 's#/\.git$##')/scripts/builder-codex-pass.sh"
  plugin-port-2026-10-25 <N> adversarial|review|final`. Main's copy finds this worktree itself
  (`builder-codex-pass.sh:769`, `WT=$PP_WORKSPACES/$UNIT`), and the merge's proof reads it with main's copy too
  (`merge-unit-local.sh` calls `$HERE/builder-codex-pass.sh --verify`, `$HERE` being main's `scripts/`). The Builder
  brief names this command; no flag, no compatibility branch, no `Mutation-verified:` line.
- A2, half settled: `orca orchestration check --terminal <this pane> --json` (2026-10-25) returned a batch with
  `result.acknowledged` (null) and `result.deliveryId`, and messages with `id`, `thread_id`, `delivered_at` (null on
  an unacknowledged batch) and no other read field. Builder check before G7: acknowledge one batch of its own, then
  read `--all --json` and see whether that message's `delivered_at` is set. Set: ask 2 follows the reply's
  `delivered_at`. Not set: ask 2 stays the existing log-tag check (:151-154), and the CHANGELOG says so.
- A3, Builder check before G9: `jq '.units.inFlight[0] | keys'` on the fixture of `dashboard-alerts.test.sh` names a
  per-pass verdict list. Present: the alert reads it. Absent: `dashboard.sh` adds `newestPass {n, verdict, top}` to the
  unit object where the card reads round reports (~458), and the alert reads that.
- A4, Builder check before G10: `rg -n 'merge-.*\.log|MERGE_LOG' scripts/merge-unit-local.sh` names the merge log
  path. Found: merge rows read it. None: merge rows show the dashboard's merged state only, said in the README.
- A5, Builder check before G8's 358 part: `rg -n merge-shas scripts` names the finished-builds file. Readable from
  `collect.py`: use it. Not: the squash commit is `git log main -1 --grep '^feat(<unit>)'` (the merge's subject), and
  the comment says it is the fallback.

## 4. Dropped, done, not applying

- Issue 345: done in 0.46.0 (section 1). Not on the Closes line; 0.46.0 closes it when main pushes.
- Host issue 3167 (issue 340), 3169 (issue 342), 3170 (issue 343), 3171 (issue 344), 3172 (issue 346), and host issue
  3168's original asks F1-F4 (issue 341): ported in 0.46.0. Evidence: `answer-worker.sh:157-170` (background follower),
  `builder-launch.sh:158-159` (PLAN-WRITTEN, PLAN-REVISED), `dashboard.sh:268-293` (`merged()`),
  `builder-codex-pass.sh:915-953` (`rebase_and_test`), `scripts/ruling-log-archive.sh`, `builder-launch.sh:82-92`
  (Data design). So host commits `f6333ed2`, `60739112`/`1fd88c1f` and `6aeaff5a` bring nothing new for the listed
  host issues. Only the host issue 3168 widening is new (G4).
- The host's typecheck skip and bugfix-lock message (`47632f56`): no plugin site (Decision G4-4).
- Issue 363: pinned, no code (G1).

## 5. Build order and size (changed lines, code + tests, estimates)

| Order | Group | Items | ~Lines |
|--:|---|---|--:|
| 0 | Builder checks A2-A5 (minutes; A2 first, the riskiest) | | 0 |
| 1 | G1 | 361 (~20), 354 (~35), 363 pins (~15) | 70 |
| 2 | G2 | 352 (~80, the shared proof predicate), 353 (~330, the stamp contract) | 410 |
| 3 | G3 | 355 | 125 |
| 4 | G4 (halfway cut after it) | 362 (~320), host 3168 widening (~80), launch fixtures (~25) | 425 |
| 5 | G5 | 359 (~80), 365 (~340, most of it deletions; worktree-setup, option tests, docs) | 420 |
| 6 | G6 | 350 (~60), host 3173 (~85), 364 part 1 (~65) | 210 |
| 7 | G7 | 351 | 200 |
| 8 | G8 | 356 (~45), 357 (~105), 358 (~50) | 200 |
| 9 | G9 | 364 part 2 (~45), 360 (~110) | 155 |
| 10 | G10 | 349 (~1,130 ported from the v2 mod: code ~660, tests ~465; manifest, docs, types ~40) and the merge gate (~25) | 1,195 |
| 11 | G11 | 348 (with release-decide.sh) | 190 |
| 12 | version, CHANGELOG, README badge (each part) | | 65 |
| | Total | | ~3,665 |

G2 to G4 edit `builder-codex-pass.sh` in order (narrowed line, hand-off, gates); G5 reads G4's gates. Halfway note in
the evidence file when G4 is green.

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| two at once | two first test runs in one session, released together | the diffstat prints exactly once | suite-rerun-guard.test.sh "two first suite runs released at once in one session print the diffstat exactly once" |
| partial failure | the fix hand-off write fails mid-way (hand-off path is a directory) | no file at the path, no helper, main told | builder-codex-pass-fresh-round.test.sh "a hand-off write that fails leaves no file at the hand-off path and starts no helper" |
| retry | report r1's Orca send fails, the Builder finishes, its worktree is removed before the next tick | the unit is neither finished nor merged while r1 is undelivered; the next tick posts r1 from its stamp, then r2; a further tick posts nothing | main-watch-report-wake.test.sh "r1's send fails, the worktree is removed, the next tick posts r1 from its stamp" |
| boundary | a judged NO-GO plan at 149 and at 150 planned lines, rulings newer | 149 launches, 150 refused | builder-launch-resume-from-plan.test.sh "a NO-GO plan at 150 planned lines is refused, at 149 taken" |
| foreign path | session A owns a tmp worktree with an uncommitted file; session B runs `git worktree add <that path> HEAD` (fails), then `git worktree remove --force <that path>` | B's remove is blocked; A's worktree and file remain | git-safety.test.sh "session B's failed add on session A's worktree path, then B's forced remove: blocked, A's worktree and its uncommitted file still there" |

## Claims to falsify

1. Issue 363's bug does not exist in the plugin (`to-main.sh:29`, `:41`; `cos-tell.sh:14`, `:20`).
2. The newest-reflog rule keeps a fresh worktree live and a merged one merged (`dashboard.sh:279-283`).
3. A merge refused for proof leaves the branch's HEAD unchanged, and a reviewed commit followed by a generated-only
   tail still merges (G2, one proof predicate at both steps).
4. After G5 nothing reads `pp_option ponytail`, `{ponytail}` or `templates/ponytail/` (`rg -n -i ponytail scripts
   hooks templates .claude-plugin config docs` shows only old comment tags, `config/retired.tsv`, the summary-hook
   cleanup's match in `worktree-setup.sh`, and fixtures naming the third-party plugin); `bash
   scripts/worktree-setup.sh "$WT" --builder` succeeds with `templates/ponytail/` gone.
5. The host items dropped in section 4 are in 0.46.0 at the lines cited.
6. The units mod writes no file (it holds atoms and in-memory caches only) and reads no stall field.
7. `release-decide.sh` says skip when the version did not change or its tag exists, and the workflow runs no tag or
   publish step without its `release` output.
8. The picker refusal never fires in a worker, reviewer or Chief of Staff pane (`ask-records-decision.sh:27-29`).
9. `git-safety.sh` blocks every forced remove of a path the session's own successful add on an absent path did not
   create, a failed add on another session's path included.
10. A report whose send failed reaches main after its worktree is removed, and no Builder unit finishes or merges
    before every finished report of it reached main.

## Rule drift map

The list main handed this unit has two messages; deduplicated, 24 lines (R1-R24, in the first message's order). The
owner ruled (2026-10-25) that this unit copies EVERY line: a line an ordered item covers rides with it, every other
line is its own item RD1-RD12 below (RD13 is the owner's background-run order, not a drift line). All are in part A. Main marks each synced in the host's drift tool after the
merge. A host sentence that names a host-only part (its memory cages and lanes, its paths, repo id, machines, model
counts) is copied as its plugin meaning or, where it has none, listed in the item as "no plugin site" with the reason.

| Line | Host section | Plugin target | Covered by |
|---|---|---|---|
| R1 | short brief template | `templates/_batch-brief-template.md` | host 3168 widening (What can go wrong), issue 362 (size line) |
| R2, R3 | brief template: Accepted failure modes, Decisions already made | plan specs, reviewer prompt | issue 362 (`Test:` per item); the reopen rule: RD1 |
| R4, R23 | brief template: Stated limits (both wordings) | plan specs, reviewer prompt | RD2 |
| R5-R7 | Builder brief: Codex passes, Done, How to work | `templates/_builder-brief-template.md` | issues 352, 359, 362, 365 |
| R8-R11 | reviewer tools: A finding is a failing test, Instruction priority and stopping, Read cold, Scope | reviewer prompt, Builder brief How to work | RD3 |
| R12 | routing roles | `config/routing.json` roles | RD4 |
| R13 | main session: Orchestrator and Advisor Role | `templates/main-session.md` Working rules :10-13 | issue 353 (report-first line); the changed sentence is RD11 |
| R14 | orchestration reference: Resource safety | `templates/global-rules.md` Working and review | issues 362, 365 hunks; the rest RD5 |
| R15, R16 | orchestration reference: Unit = one Orca worktree, Visibility and ledger | `templates/global-rules.md` Working and review | RD6 |
| R17 | adversarial reviews | `templates/global-rules.md` Working and review | RD7 |
| R18 | comments: never write the add-on's name in a comment | `templates/global-rules.md` Working and review | RD8 (with issue 365) |
| R19 | planning rules | `templates/global-rules.md` | issues 359, 362, 365 |
| R20 | startup: Operating Rules | `templates/AGENT_STARTUP.md` Rules for every pane | RD9 |
| R21 | brief template: Assumptions, Claims to falsify, Plan change log | plan specs | issue 359 |
| R22 | brief template: Data design, Prior art | `templates/_batch-brief-template.md` :46-52 | Prior art in the plugin already (:40); the Data design obligations are RD12 |
| R24 | agents: Compact Instructions | `templates/global-claude.md` | RD10 |

## Rule drift items (part A, group G12, built after G9)

Each is rule text unless it says otherwise; each test is a text check in `scripts/__tests__/brief-template.test.sh`
(it already reads these templates) unless named. No item adds a conditional write or safety check, so none has a
`Break:` line.

- RD1 (R2, R3). Reopen rule. `builder-codex-pass.sh` `LIMITS_HEAD` (:169) and the plan-author lines (`seat.sh:412-414`):
  a finding reopens an accepted failure mode, a decision or a stated limit only when it proves the item's factual
  premise false or shows the goal defeated, with a concrete counterexample; reviewers cite the line otherwise. Issue
  359 left this out pending the owner; the owner's copy-every-line ruling is that ruling. ~10 lines. Test:
  builder-codex-pass.test.sh "the review prompt reopens a decision only on a concrete counterexample".
- RD2 (R4, R23). Stated limits heading: `(every reviewer is handed these; a finding beyond one is out of scope: a
  follow-up issue, never a blocker)`, in `LIMITS_HEAD` and the plan-author lines; each limit is a measured bound (the
  number, the command, the date). It governs later plans' Stated limits sections; this unit's own order (every
  finding blocks) is unchanged, and this plan has no Stated limits section. ~6 lines. Test: builder-codex-pass.test.sh
  "a finding beyond a stated limit is a follow-up, never a blocker".
- RD3 (R8-R11). The reviewer prompt (`builder-codex-pass.sh` `FORMAT` :103, `GUIDANCE` :110) and the Builder brief's
  How to work. Copied: a P0-P2 finding carries a complete failing test file in a fenced block naming its path, written
  to fail on the diff as it stands, or its exact failing input when a test would cost more, with the reason in one
  line; a P2 or P3 whose test is written and whose fix is under ten lines may carry the fix as a fenced unified diff
  (the Builder applies it, runs the test green, and the next pass reads it; a reviewer never reviews its own fix);
  the brief and the dispatch spec outrank the startup file and every skill, and a reviewer that stops early quotes
  the instruction that stopped it; inside the read-only sandbox an Orca call answering `runtime_unavailable` is by
  design, not a failure to retry or report; read the diff, then the brief, draft the findings, and only then the
  evidence file; open a file outside the diff, the brief and its named callers only to confirm or refute one finding,
  and say which; never open a generated file. No plugin site: the host's test runners, file paths and model-pausing
  note. ~30 lines. Test: builder-codex-pass.test.sh "the review prompt carries the failing-test default, the cold-read
  order and the scope rule".
- RD4 (R12). Routing roles, compared field by field (`jq '.roles'` on both sides, 2026-10-25). Agents, models (as
  family names: `config/routing.json`'s note forbids versions) and efforts match, except one: the host's first fix
  round keeps the Builder's launched model and effort (`firstPass` null), the plugin's runs Opus high
  (`roles.fixer.first`). Copied: `roles.fixer.first` becomes `{"model": "builder", "effort": "builder"}`, the value
  `builder-fresh-round.sh:131-132` already reads; the `fixerFirstModel` and first-effort descriptions in
  `.claude-plugin/plugin.json` (~47-60) say so. A behaviour change for installs that keep the default: the CHANGELOG
  says it. ~8 lines. Test: builder-fresh-round.test.sh "with no /plugin key the first fix round keeps the Builder's
  launched model and effort".
- RD5 (R14). Resource safety, copied as plugin meaning: no duplicate agent of any role (already `global-rules.md:70`);
  never stop a driver and relaunch it without reading its log tail; after a crash resume, never restart (`claude
  --continue` or `codex resume --last`, then "Orca restarted; continue from your last message."); interrupt before
  closing a resumable pane, close reviewers after their verdict; memory, not a pane count, is the limit (the pane
  gate, `config/pane-budget.json`). No plugin site: the host's node heap flag, lane counts, cgroups, systemd scopes,
  pane box (the plugin ships none: `config/routing.json:9`), machine figures and typecheck cache. Not copied: "never
  launch agents with setsid or nohup", which contradicts `seat.sh run`'s setsid detach (0.46.0, chosen on a probe);
  Decision RD-1 below. ~10 lines.
- RD6 (R15, R16). Units and visibility: one unit is one worktree, one branch, one squash merge; never two workers in
  one worktree, and units touching the same files are combined; a ready brief is dispatched at once unless it overlaps
  another unit (serialize only overlaps); main removes the unit's panes and worktree in the merge turn and reconciles
  orphaned worktrees at every plan start; briefs run ahead of builds; main verifies every dispatch (status shows only
  scope, the diff stat matches each claimed change, the worktree and main heads are as expected, a pass claim carries
  runner totals); every worker is an Orca pane the owner can open, Orca's task list is the dispatch ledger, and
  anything main did not start is reconciled before acting. No plugin site: the host's repo id, paths and model
  limit. `global-rules.md:60` keeps its units-by-area line. ~14 lines.
- RD7 (R17). Adversarial reviews: every reviewer covers the same full scope (areas are never split between
  reviewers); no reviewer test runs at round close, each goes to the fixer, who runs it red first; code comments never
  name reviewers, rounds or P-levels; a reviewer's findings are read with `read-verdict.sh`, never a raw pane read.
  The failing-test and cold-read lines are RD3's. ~6 lines.
- RD8 (R18). Never write the add-on's name as a tag in a code comment; a simplification is explained in a plain
  comment; existing tags change only when their lines are edited or in a requested sweep (so issue 365's "old tags
  stay" holds). ~4 lines.
- RD9 (R20). `templates/AGENT_STARTUP.md` Rules for every pane gains what it lacks of: own in-scope work end to end;
  plan first for multi-step work and read the real code before editing; before editing auth, verification, billing,
  tenant isolation or deploy tooling, write the plan down and list every caller of what changes; fix every in-scope
  copy of a bug pattern; confirm first before an irreversible destructive action, and no destructive git command
  unless asked (`hooks/git-safety.sh` enforces). The refusal line is there already (:77). ~8 lines.
- RD10 (R24). `templates/global-claude.md` gains `## Compact Instructions`: when compacting keep the task or brief
  path and the evidence file path, the current cut and its test state, the last round file and its open findings,
  open decision ids and the files changed; drop file dumps and tool output. Main still never compacts
  (`templates/main-session.md:35`). ~5 lines. Test: install-lib.test.sh "the global CLAUDE.md template carries Compact
  Instructions" (or brief-template.test.sh, whichever reads `global-claude.md` today).
- RD11 (R13, a changed sentence, not already copied). The host's main-session rule lets main edit code itself, with
  larger work going to a Builder and review and merge rules unchanged for main's code; the plugin's
  `templates/main-session.md` :10 ("an edit to project code -> a batch brief") and :11-13 ("Main writes only
  intents, briefs, findings and config ... routes findings, never fixes them") forbid it. Copied as plugin meaning:
  :10's Do-not row becomes "a large code change in main -> a batch brief, then `builder-launch.sh`"; :11-13 say main
  may make a small code fix itself, with the main-edit guard off (`hooks/main-edit-guard.sh:72` already reads
  `.claude/approvals/main-edits-ok`, gitignored; the owner creates it), larger work runs as a Builder, and main's
  code takes the same review and merge rules. No guard code changes. ~6 lines. Test: brief-template.test.sh "main's
  rules let main make a small code fix with the main-edit guard off".
- RD12 (R22, the Data design obligations not already present). `templates/_batch-brief-template.md` Data design
  (:46-52) asks where state lives, who writes and reads it, when it resets and what a retry runs; the host's adds,
  for each persistent piece of state: what is left if a write fails halfway and how it recovers; what happens on two
  concurrent writes; which code owns retries and its limit. The placeholder line (:52) gains `; a half write leaves
  <what>, recovered by <how>; two concurrent writes <result>; retries owned by <code>, at most <n>`. Prior art
  (:40) is already the host's. ~5 lines. Test: brief-template.test.sh "the batch template's Data design asks for
  half-write recovery, concurrent writes and retry ownership".
- RD13 (the owner's order of 2026-10-25 for this unit, a rule change). `templates/main-session.md:7` and
  `templates/_builder-brief-template.md:128-129`: every test run starts with Bash `run_in_background`, whatever its
  expected length, and every other command that can run in the background does; only quick reads stay in the
  foreground. The "over 60 seconds" qualifier for tests goes (:128). Main's row at :7 reads: "a test run of any
  length, a long job, or any other command that can run in the background, in main's foreground -> its own pane, or
  `run_in_background` and `wait-test-run.sh <pid> <file>`; only quick reads stay in the foreground". ~6 lines. Test:
  brief-template.test.sh "every test run starts in the background whatever its length, in main's rules and the
  Builder brief" (it also checks the "over 60 seconds" wording is gone from the test rule).

Decision RD-1. The setsid line of R14 is not copied: the plugin's detach is the 0.46.0 fix for a seat run dying with
main's pane, tested there; copying the host line would reverse it. Main may overrule. Test:
`scripts/__tests__/seat-run.test.sh`, its existing setsid case (unchanged).
Decision RD-2. Host-only sentences are listed per item with the reason, not silently left out. Test: none, a
reviewer reads each item's "No plugin site" list against the host section.

## Contracts (Produces / Consumes across groups)

The pass script (`builder-codex-pass.sh`) is one producer edited by G2, G3, G4 and G8; the dashboard snapshot is the
producer G9 and G10 read. Every existing consumer is named; a change to a shape updates its consumers in the same
group.

- G2 round file. Produces: `.claude/briefs/<u>-r<N>-reports.md` keeps its header lines (`Pass: <kind>` and
  `Timing:`, :1232) and its last non-empty line `VERDICT: GO|NO-GO`; a narrowed GO adds a stdout line `NARROWED GO:
  this GO merges nothing. Next: builder-codex-pass.sh <u> <N+1> final; ...` (stdout only, not in the file). On a pass
  that fails before the verdict, no `VERDICT:` line, as today. Consumes: `read-verdict.sh` (:107, :117, :161, the
  last line), `builder-codex-pass.sh --verify` (merge proof), `main-watch.sh` `round_line`/`report_wake` (new: the
  `Pass:` line and the last line), `board.sh` stopped-panes loop (new), `dashboard.sh` ~458 (the card),
  `builder-fresh-round.sh` (the fix file next to it). A file with no `Pass:` line reads as "pass kind not recorded",
  never as a kind.
- G2 report stamp. Produces: `$ST/due-report-<u>-r<N>-<cksum>`, four lines (unit, round, subject, body), published by
  `mv`; removed once its item is delivered. Consumes: `report_send`, `report_pending` only.
- G3 fix hand-off. Produces: `<u>-fix-r<N>.md` published whole by `mv` (never partial), or no file and the line `NO
  FIX HAND-OFF after pass <N>: <check> (<value>)` (stdout and, with a Builder seat, a `to-main.sh question`); the
  seat record line `fixer=<rule> model=<m> effort=<e> round=<N>`. Consumes: `builder-fresh-round.sh` (:112, the
  name's N), main's wake (the question), `dashboard.sh` (round files only; the seat line is new and nothing else
  reads it).
- G4 gates. Produces: refusals on stdout/stderr with exit 2 at launch (`REFUSED: <file> has no <section>`, the
  `untested <item>` list) and non-zero before pass N (`Sites checked`, `Break:` without `Mutation-verified:`), no
  round file written on a refusal. Consumes: the Builder (fixes and re-runs), main (`builder-launch.sh` output),
  the launch tests. The plan-facts awk consumes the plan's `- Planned size:`, `## Decisions`, `## Accepted failure
  modes` and `## What can go wrong`, which G5's plan-author lines (`seat.sh:412-414`) produce.
- G8 report header. Produces: one more header line, `Pre-review: rebase <s> s, tests <s> s, precheck <s> s` (`not
  run` for a step skipped), beside `Timing:`. Consumes: humans and `read-verdict.sh`, which reads only the last
  line, so no consumer parses it; `round_line` ignores it.
- G9 dashboard alerts. Consumes: the snapshot's unit object (`units.inFlight[]`), per A3 either an existing per-pass
  verdict list or a new `newestPass {n, verdict, top}` that `dashboard.sh` ~458 produces. Produces: an alert
  `{id: "pass-loop-<u>-r<N>", ...}` in the alerts list the existing `cos-watch-alerts.sh` reads by id (its seen file).
  A missing `newestPass` raises nothing (no alert from absent data).
- G10 units mod (part B). Consumes: the snapshot fields listed in Decision G10-1; a missing field renders nothing.
  Produces: no file (atoms only). If A3 adds `newestPass`, the mod does not read it.

## Parts

### Part A -- plugin-port-2026-10-25 (this unit)

Items: local commit 6da84e5 (section 0); issues 350-365 and host issue 3173 (sections 1-2, G1-G9); RD1-RD13 (G12).
Version 0.47.0, unless another unit takes it first. Closes: the `Closes:` line at the top.
Build order: A2, A3, A5 (A2 first), then G1, G2, G3, G4 (halfway cut), G5, G6, G7, G8, G9, G12, version and
CHANGELOG. Every pass runs main's pass script (A1).
- Planned size: ~84 files, ~2470 changed lines (G1-G9 ~2,215, G12 ~190, version ~65). Over the 40-file cap and over
  60 files: section "Question for Max" proposes A1/A2.
Done when: the common Done when below, for every G1-G9 and RD item; the 6da84e5 tests green on the tip.

### Part B -- plugin-port-mod-2026-10-25

Items: issue 349 (G10, with its merge gate) and issue 348 (G11). Assumption A4 belongs to it.
Version: the next free minor when its build starts (0.48.0 after part A's 0.47.0). Closes (part B) line at the top.
Build order: A4, then G10 (field table in the evidence file first, Decision G10-1), G11, version and CHANGELOG.
- Planned size: ~25 files, ~1450 changed lines (G10 ~1,195, G11 ~190, version ~65). Within the 40-file cap and the
  3,000-line review limit.
Done when: the common Done when below, for G10 and G11 only; `claude plugin test .` and `claude plugin validate .`
pass from the merge gate; the backfill step (item 6) is part B's.

## Not ordered (found, not planned)

- Plugin issues 340 to 344, 346 and 347: not in this unit, by the order.

## Version and CHANGELOG

Main carries 0.46.0 (`.claude-plugin/plugin.json:3`). This unit takes the next free minor when its build starts:
0.47.0 unless another unit takes it first (with a split, each part takes the next free one). The README badge by
hand (`scripts/__tests__/plugin.test.sh` checks it). One CHANGELOG entry in the 0.46.0 format: a paragraph per group,
the CHANGELOG's own issue form, "Closes" on every issue of the Closes line, and the two issue 355 asks not built
(Decision G3-1). It also names local commit 6da84e5's fix.

## Files edited

- G1: `scripts/builder-codex-pass.sh` ~897-907; `scripts/dashboard.sh` ~271-283; tests
  `scripts/__tests__/builder-codex-pass.test.sh`, `scripts/__tests__/dashboard-merged-unit.test.sh`,
  `scripts/__tests__/to-main.test.sh`, `scripts/__tests__/cos-tell.test.sh`
- G2: `scripts/builder-codex-pass.sh` ~1250; `templates/_builder-brief-template.md` ~239; `scripts/merge-unit-local.sh`
  ~234-261 (the `prove` function and its two calls); `scripts/main-watch.sh` ~205 (`delivered` beside `post`), ~325,
  ~1114 (the fence), ~1140, ~1466 (`report_send`) and the new helpers; `scripts/board.sh` ~199-235;
  `templates/main-session.md` Details; tests `scripts/__tests__/builder-codex-pass-closing.test.sh`,
  `scripts/__tests__/merge-unit-local.test.sh`, `scripts/__tests__/main-watch-report-wake.test.sh` (new),
  `scripts/__tests__/board.test.sh`, `scripts/__tests__/read-verdict.test.sh`
- G3: `scripts/builder-codex-pass.sh` ~1236-1313 and its EXIT handler; `scripts/builder-fresh-round.sh` ~106-141;
  tests `scripts/__tests__/builder-fresh-round.test.sh`, `scripts/__tests__/builder-codex-pass-fresh-round.test.sh`
- G4: `scripts/builder-launch.sh` ~82-92, ~146-162; `scripts/builder-codex-pass.sh` ~829-850, ~1027, ~1038, ~1263,
  ~1260-1310; `templates/_builder-brief-template.md`; `scripts/seat.sh` ~412-414; `templates/_batch-brief-template.md`
  (What can go wrong heading); tests `scripts/__tests__/builder-launch-resume-from-plan.test.sh`,
  `scripts/__tests__/builder-codex-pass-class-return.test.sh`, `scripts/__tests__/builder-codex-pass-decisions.test.sh`,
  `scripts/__tests__/fixtures/builder-launch-resume-setup.sh` ~32, `scripts/__tests__/builder-launch-resume-launch-line.test.sh`
  ~26-37 (`scripts/__tests__/builder-launch-resume-rollback.test.sh` and `builder-launch-resume.test.sh` run
  unchanged on the updated fixture)
- G5: `scripts/seat.sh` ~412-414; `templates/main-session.md` ~55-64; `templates/_builder-brief-template.md` ~26 and
  the pre-flight lines; `scripts/builder-codex-pass.sh` ~1038; `templates/global-rules.md` ~5, ~89-91;
  `templates/ponytail/LICENSE`, `SKILL.md`, `SUMMARY.md` (deleted); `.claude-plugin/plugin.json` ~226-232;
  `scripts/paths.sh` ~1137, ~1156; `config/addons.tsv` ~6; `config/retired.tsv` (~2 and one row, lint only);
  `scripts/builder-launch.sh` ~252-255; `scripts/setup.sh` (lines in G5); `scripts/install-lib.sh` ~493-499;
  `scripts/worktree-setup.sh` ~21, ~72-78, ~97-98, ~186-227; `skills/setup/SKILL.md` ~192-197;
  `skills/uninstall/SKILL.md` ~18; `hooks/dependency-addition-guard.sh` ~3, ~42, ~278; `docs/add-ons.md`,
  `docs/commands.md`, `docs/setup-questions.md`, `docs/worker-panes.md`, `docs/uninstall.md`, `docs/configuration.md`
  ~48, ~57; tests `scripts/__tests__/plugin-option.test.sh` ~6-52, ~201-242, `scripts/__tests__/rules-audit.test.sh`
  ~20,
  `scripts/__tests__/brief-template.test.sh`, `scripts/__tests__/builder-codex-pass.test.sh`,
  `scripts/__tests__/install-lib-setup.test.sh`, `scripts/__tests__/profile-revoke.test.sh`,
  `hooks/__tests__/profile-settings.test.sh`, `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/update.test.sh`,
  `hooks/__tests__/dependency-addition-guard.test.sh`, `scripts/__tests__/worktree-setup.test.sh` (where they assert it)
- G6: `hooks/ask-records-decision.sh` ~33, ~73-88; `hooks/suite-rerun-guard.sh` ~150 and its final write;
  `hooks/cos-unfinished-stop.sh` (new); `hooks/hooks.json` ~99-105; `docs/hooks.md`; tests
  `hooks/__tests__/ask-records-decision.test.sh`, `hooks/__tests__/suite-rerun-guard.test.sh`,
  `hooks/__tests__/cos-unfinished-stop.test.sh` (new), `scripts/__tests__/plugin.test.sh`
- G7: `scripts/paths.sh` ~580-600; `scripts/answer-worker.sh` ~38, ~54-70, ~151-170; `scripts/ask-main.sh` ~31-59;
  tests `scripts/__tests__/answer-worker.test.sh`, `scripts/__tests__/ask-main.test.sh`
- G8: `scripts/builder-codex-pass.sh` ~915-953, ~1232; `hooks/git-safety.sh` ~224-225, the add branch and the
  `--record-add` mode; `hooks/hooks.json` PostToolUse Bash (one registration; `scripts/__tests__/plugin.test.sh`'s
  hook count and `docs/hooks.md` follow, as in Decision G6-3);
  `skills/worktreereview/scripts/collect.py` ~486-497, ~904; `skills/worktreereview/scripts/render.py` ~210-211; tests
  `scripts/__tests__/builder-codex-pass-rebase.test.sh`, `hooks/__tests__/git-safety.test.sh`,
  `scripts/__tests__/worktreereview.test.sh`
- G9: `scripts/dashboard_alerts.jq` ~56-75 (and `scripts/dashboard.sh` ~458 if A3 says absent);
  `hooks/agent-startup-context.sh` ~104-145; `templates/cos-order.md` (new); `scripts/cos-order-check.sh` (new);
  `docs/chief-of-staff.md`; tests `scripts/__tests__/dashboard-alerts.test.sh`,
  `scripts/__tests__/cos-order-check.test.sh` (new), `hooks/__tests__/agent-startup-context.test.sh`
- G10: `hooks/units.tsx`, `hooks/units-sources.ts`, `hooks/units.test.tsx`, `hooks/units-sources.test.tsx` (all new,
  from `84118aa9`); `hooks/hooks.json` ~2; `.claude-plugin/plugin.json` (three options); `types/index.d.ts`;
  `scripts/merge-unit-local.sh` touched-tests step; `docs/dashboard.md` (a units section, from the host README);
  tests `scripts/__tests__/merge-unit-local.test.sh`, `scripts/__tests__/plugin.test.sh` (option count)
- G11: `.github/workflows/release.yml`, `scripts/release-decide.sh`, `scripts/release-notes.sh`,
  `scripts/release-backfill.sh`, `scripts/__tests__/release-notes.test.sh` (all new); `scripts/update.sh` ~27
- G12: `scripts/builder-codex-pass.sh` ~103, ~110, ~169; `scripts/seat.sh` ~412-414; `config/routing.json` roles;
  `.claude-plugin/plugin.json` ~47-60; `templates/global-rules.md` Working and review; `templates/AGENT_STARTUP.md`
  Rules for every pane; `templates/global-claude.md`; `templates/main-session.md` ~7, ~10-13;
  `templates/_builder-brief-template.md` How to work, ~128-129; `templates/_batch-brief-template.md` ~46-52; tests
  `scripts/__tests__/brief-template.test.sh`, `scripts/__tests__/builder-codex-pass.test.sh`,
  `scripts/__tests__/builder-fresh-round.test.sh`, `scripts/__tests__/install-lib.test.sh`
- Version: `.claude-plugin/plugin.json` ~3, `README.md` badge, `CHANGELOG.md`

## Done when

1. Each item's named test in section 1 and section 2 is green, the `Break:` targets read true to a reviewer, and the
   6da84e5 tests (`plan-tier.test.sh`, `answer-worker.test.sh`) are green on the tip.
2. `bash scripts/run-shell-tests.sh --changed main` is green, plus the callers' tests each group names;
   `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh`
   pass.
3. Builder checks A2-A5 are answered in the evidence file with their outputs; G10's field table is there; every
   round file of this unit was written by main's pass script (A1).
4. Version 0.47.0 (or the next free minor), the badge and one CHANGELOG entry with every Closes issue.
5. A closing (final) pass ends `VERDICT: GO` with no finding named. Every finding P0 to P3 before that went back to a
   fix round.
6. Main, after the merge: marks the mapped drift lines synced; runs `scripts/release-backfill.sh` only after the push,
   on the owner's go.

## Main answers

1. Worktree ownership: granted only after a successful add on a path proven absent before it (PreToolUse `pending`, PostToolUse `owned`); the failed-add test on another session's path is in G8.
2. Ponytail removal: `scripts/worktree-setup.sh` (:73, :197) and its summary-hook cleanup, `plugin-option.test.sh` and `docs/configuration.md` (:48, :57) are in G5; `config/retired.tsv` is a lint row only; no installed-copy cleanup is planned (count unknowable, section "Question for Max").
3. Report delivery: the host's stamp contract (`due-*`, `report_send`, the `report_pending` fence before finish and merge) is ported in G2, with the worktree-removed retry test.
4. Merge proof: one `prove` predicate runs before and after the rebase, so a generated-only tail stays accepted (G2).
5. Units mod: part B ports the v2 mod as `84118aa9` leaves it, no stall mechanic and no stall producer (G10).
6. Launch fixtures: the shared fixture and the missing-Data-design assertions move to the new refusals; no compatibility path, no time-limit raise (G4).
7. Release guard: the workflow calls `release-decide.sh`, which the tests run, and a text check pins every later step to its output (G11).
8. R13 and R22: mapped as changed lines, RD11 (main may make a small code fix) and RD12 (the Data design obligations).
9. `Catches:` lines on every new flow step; section "Contracts" holds Produces/Consumes for G2/G3/G4/G8 and G9/G10.
10. Self-gating: this unit's passes run main's pass script with the command in A1; the new gate binds from the next unit.
11. Background runs: RD13 makes every test run start in the background whatever its length, in `templates/main-session.md:7` and `templates/_builder-brief-template.md:128`.

## Question for Max

1. Existing ponytail installs. Installs carrying a saved `ponytail` answer: 0 on this machine (checked 2026-10-25: no
   `~/.commandeck/install/`, no `ponytail` key in a project `commandeck.json` or in the plugin's `pluginConfigs`);
   every other install is unknowable (a public plugin, no install registry). So this unit plans no cleanup of an
   existing install: an installed ponytail skill copy and a saved answer stay where a setup put them, read by nothing.
   Choose: (a) leave it so, the CHANGELOG telling owners to remove the skill by hand; or (b) a follow-up unit that
   removes the installed copy through the installation helpers (`scripts/install-lib.sh` `il_own`, :998), only where
   the install manifest shows setup placed it.
2. Part A's size. ~84 files and ~2,470 lines, over 60 files. Proposed split along group lines, part A1 merging first:
   - Part A1, plugin-port-2026-10-25: local commit 6da84e5, G1, G2, G3, G4, G6, G7 (issues 350-355, 361-364 part
     1, host issue 3173): the pass, report, merge and launch loop, hooks and answers. ~43 files, ~1,505 lines.
   - Part A2, a new unit after A1 merges: G5, G8, G9, G12 (issues 356-360, 364 part 2, 365, every drift line, RD13):
     the planning text, ponytail removal, worktree and review tooling, Chief of Staff rules and rule drift. ~48
     files, ~1,030 lines. It depends on A1: G5 writes the plan-author lines G4's launch gate reads, G9's alert relies
     on G2's report delivery, and both edit `builder-codex-pass.sh`, `templates/_builder-brief-template.md` and
     `scripts/paths.sh`.
   Part B stays as planned, after A2. Or keep part A whole as planned.

## Plan change log

- 2026-10-25, revision 1 (answers the plan judge's NO-GO; main's rulings 1-11):
  - G8 357: ownership needs an absent path before the add and a worktree after a successful call (PostToolUse); new
    failed-add, `; true` and pending-only tests; Decision G8-1 rewritten; What can go wrong row "foreign path"
    replaces the units "empty" row (the units case stays as Decision G10-2's test).
  - G5 365: `scripts/worktree-setup.sh` callers :73 and :197 removed, its summary-hook cleanup kept; `plugin-option.test.sh`
    and `docs/configuration.md` :48, :57 added; `config/retired.tsv` described as a lint list; Decision G5-2 replaced
    (no install cleanup, count 0 here, unknowable elsewhere); `setup.sh` `TAKES` :55 added.
  - G2 353: the host's durable report contract (`due-*` stamps, `report_send`, `report_pending` fence in `seat()`)
    replaces the rescan; Decision G2-5; the retry row and Claim 10.
  - G2 352: one `prove` predicate before and after the rebase replaces the single pre-rebase `--verify`; Decision
    G2-6; Claim 3 widened.
  - G10 349: ported from `84118aa9` (v2 layout, stall mechanic removed): no `unitsStallMinutes`, no stall producer;
    field list updated; tsconfig and README mapped; Decision G10-3.
  - G4: launch fixtures and the missing-Data-design assertions updated; Decision G4-3 now removes the 0.46.0 Data
    design exception; its "Not ordered" entry removed.
  - G11 348: `scripts/release-decide.sh` is the decision path the workflow calls and the tests run; Break lines
    rewritten; Claim 7.
  - Rule drift: R13 (RD11) and R22 (RD12) mapped as changed lines; RD13 added (every test run in the background).
  - `Catches:` lines on every new flow step; new section "Contracts".
  - A1 settled: main's pass script, with the command.
  - Timed checks: the new heavy cases' files named, none has a time-bound check.
  - Sizes re-stated (part A ~84 files, ~2,470 lines; part B ~25 files, ~1,450 lines); "Main answers" and "Question
    for Max" added.

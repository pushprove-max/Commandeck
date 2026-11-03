# Plan: commandeck-gap-copy-2026-11-03

Owner's words: the owner, 2026-11-03: copy into the plugin what is missing from the host's rules, hooks and scripts. A straight copy, not a redesign. One unit for all of it, no split, whatever the size caps say.

Goal: Copy into the plugin every generic host rule, hook and script the 2026-11-03 gap report lists as missing or behind (G1-G10), host-only parts dropped, each with the host's tests.

Tier: Standard; LOCAL merge only; changed-file tests only; tests run on the PC; no test-timeout raises.
Split override: the owner's order names one unit, no split, whatever the size caps say.
Source: the host checkout named in the batch, at its main as of the build start (963f5989d when r1 and r2 were written; the gap report read 0c01c20ca).

- Planned size: 77 files, 6700 changed lines

New tests: commandeck-gap-copy-2026-11-03 454 -- 384 carried check labels (grep -cE '^[[:space:]]*check[[:space:]]+"' per host file: 369, plus main-background-only's 15 rw_check and both_check, 2026-11-03), less 103 in dropped parts (pre-push 52, pre-commit 20, brief-freshness-gate 22, peer-code-sync 5, bash-write-rules 2, compact-readback 1, the test-coverage row 1), plus about 60 carried bash-guardrails cases, 25 new-test-count, 33 plain-assert, 7 baseline-raise (3 case_ lines, 4 in the merge test), 12 card checks (host agent-startup-context test) and 36 new (r11: a queued wake, two wiring checks); each Acceptance case names one test or a group; the two guard rows name existing checks, none new
Timed checks: bash-guardrails.test.sh's existing cases run before the new wake, long-job, main-gate, no-Orca and hint cases, which go at the file's end; new-test-count.test.sh's and test-skip-only-blocker.test.sh's new cases go at their ends; main-script-card.test.sh's two timed checks ("a failing --help adds no line", "a slow --help holds nothing up", under 12 s) are the last cases in its file; every other carried test is a new file; no timeout raised.

## Why

The gap report found 18 missing and 8 behind rows between the host's rules and the plugin. The owner wants the generic ones copied as the host has them, host names, paths and ruling ids out. A row the plugin already does is skipped with the line that proves it (D2); a host file with a host-only input or no reader is skipped with it named (D2b); a refusal 0.68.0 made a note stays a note (D3). Rounds r3-r8 fixed copies that broke in the plugin's layout or setting, fixtures and rule text (D21-D49); the owner's answers are D22-D47 and the change log. r9 runs the carried ledger tests from a scratch main checkout, since a linked worktree drops their fixture workspaces value, reads bash-write-rules' rules from the caller's project, and fixes two long-job slips. r10 fits the copies to the plugin's repo-wide guard tests, found by running those tests on a scratch tree holding the raw host copies (## Guard fits), and makes two carried tests able to fail. r11 fits the carried wake-on-exit test to D34's to-main route and every other carried test to the D-lines, found by grepping each host test, and cuts a board.sh claim. Open below: Q-H, Q-I.

## Prior art

- Source: the host's own files (straight copy, owner's order); no library or service is added.
- Standard: githooks(5) for the .githooks files; Claude Code hook events and matchers as hooks/hooks.json already uses them.
- Conventions kept: run-hook.sh wrapper, `# Retire when:` and hook_fire_log_arm in each hook, COMMANDECK_* env names, PP_* paths from scripts/paths.sh, check-label shell tests, rules-details.md stubs.
- Paved road: no dependency added; the TypeScript reader uses the project's own typescript when present (D4).

## Data design

| state | where | writer | reader | reset | retry |
|---|---|---|---|---|---|
| plan status | .claude/plans/<plan>.status.json | scripts/plan-status.sh | hooks/lib/pane-budget.sh | rewritten per call | same call rewrites |
| phase queue | .claude/phase-queue.md, .claude/phase-queue.paused | the session the owner told to work through all phases (global-rules line, C1) | hooks/phase-queue-stop.sh | file deleted, all boxes ticked, BLOCKED line or paused | Stop re-reads it |
| queue owner | ${COMMANDECK_PHASE_QUEUE_DIR:-~/.commandeck/phase-queue}/<sha1 of project> | phase-queue-stop.sh: the first session to Stop after the queue is written | the same hook | a rewritten queue is adopted again | n/a |
| long jobs | $PP_SCRATCH/long-jobs/ (lock, log, exit file, .read mark) | scripts/long-job.sh | long-job.sh list/wait, bash-guardrails Try line | prune subcommand | start refuses a running name; an undelivered done message stays unread for wait |
| project rules | `<git top of payload .cwd, else $PWD>/.claude/rules`; that top is the root (host: `../rules` beside the hook, D20) | the project | hooks/bash-write-rules.sh | n/a | n/a |
| rule-injected marks | $PP_SCRATCH, per session | hooks/bash-write-rules.sh | the same hook | new session | n/a |
| handoff mark | ~/.claude/checkpoints/<sid>.handoff | hooks/compact-readback.sh (compact in main on the strict tier under Orca, checkpoint not yet delivered, no user-level readback registered; D31) | hooks/context-clear-stop.sh, hooks/context-line.sh | hooks/lib/context-clear-restart.sh removes it | touch is idempotent |
| delivery proof | ~/.claude/checkpoints/<sid>.md.delivered | hooks/resume-context.sh (existing) | compact-readback.sh (new reader) | context-clear-restart.sh removes it | n/a |
| local main ref | the repo's refs/heads/main | hooks/peer-code-sync.sh (fast-forward only; never while merge-unit-local.state names a live pid, D32; only under `flock -n` on merge-unit-local.lock, D48) | git | n/a | a non fast-forward changes nothing |
| baseline-raise reason | the unit's squash commit message | scripts/merge-unit-local.sh --baseline-raise (D36) | git log | per merge | a refused merge is run again with the flag |
| ruling log | ~/.claude/rulings/<project>.jsonl (COMMANDECK_RULING_LOG) | hooks/ruling-log.sh (existing) | scripts/repeat-report.sh (new reader, D42) | n/a | rerun rereads |
| token ledger | stdout | scripts/token-ledger.sh | plan-status.sh (TOKEN_LEDGER_SCRIPT names the script) | per run | rerun recomputes |
| memory files | ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/memory | scripts/memory-flush.sh | Claude memory | n/a | same names overwrite |
| commit messages | .git/COMMIT_EDITMSG | .githooks/commit-msg (trailer strip) | git | per commit | n/a |

## What can go wrong

| case | input or starting state | expected | test |
|---|---|---|---|
| worker-checkout guard blocks the plugin's own flow | the owner's checkout wires .githooks; the Fast lane, builder-launch or builder-codex-pass commits in a linked worktree | the Fast lane at $PP_WORKSPACES/Fast-lane commits; the two scripts commit with COMMANDECK_ALLOW_AGENT_GIT=1; a bare linked commit and a Fast-lane folder elsewhere are refused | githooks-pre-commit.test.sh: only the canonical Fast lane commits |
| bad input to a hook or the counter | payload field absent or missing (bash-write-rules' .cwd: $PWD; outside a checkout: no rule); junk or trailing text after the command; empty command or message; a quoted `tail -f` inside an echo | call passes, no refusal, no rewrite (the empty message and empty counter input: C8 and C4 Bad input) | bash-guardrails.test.sh: quoted, empty and junk commands pass |
| timing: a merge holds main during the sync | a merge takes merge-unit-local.lock while peer-code-sync's fetch runs (the state check already passed) | the fast-forward does not run; one line, main not moved, exit 0; the merge waits only for the sync's lock | peer-code-sync.test.sh: a merge that starts mid-fetch leaves main unmoved |
| limit: a main with no Orca | ORCA_TERMINAL_HANDLE unset (pp_is_main_pane says main), strict tier, a lone `gh run watch` or `npm test` | no rewrite to long-job or wake-on-exit; the default-tier note; the command runs | bash-guardrails.test.sh: a main with no Orca gets the note |
| odd data: a Python test with a `fit(` call | a strict-tier Write of tests/test_model.py, and of tests/rows.test.py, holding `model.fit(X, y)` after D27 | both allowed (D33); rows.test.py is refused today ((o)) | test-skip-only-blocker.test.sh: a model.fit( test passes |

## Decisions already made

1. D1 Copy the generic and missing; skip host-only inputs, jobs a plugin file does, what nothing reads or fires.
   Test: none, a scope rule (D2, D2b).
2. D2, D2b Skipped: ## Not copied lines 1 (plugin does it) and 2 (host-only input or no reader); D14 G10 Adjacent: no host rule; D24 Owner: unit-ready, unit-map, evidence-facts out.
   Test: none, nothing is built.
3. D3 Owner Q1: a refusal 0.68.0 made a note stays one (compound gh run watch, tail -f, suite run; main-background-only's fallback); rewrites, Stop refusal stay.
   Test: bash-guardrails.test.sh: tail -f into grep gets a note
4. D4 new-test-count keeps its call, line-1 count, labels, exit 0, --edited; host Python and TypeScript readers behind it, regex without typescript.
   Test: new-test-count.test.sh: no typescript: label regex
5. D5 A moved or renamed test counts as new (owner Q2; Test edits).
   Test: new-test-count.test.sh: a moved test counts as new
6. D6 Names: COMMANDECK_ env; host /tmp, cache paths to $PP_SCRATCH, ~/.commandeck; issue numbers, ruling ids, owner, account names cut.
   Test: ci/leak-test.sh (CI's leak step)
7. D7, D29 Short lines in global-rules.md (200-line cap); long text in rules-details.md behind two stubs (## Rule text); test-rules.md, AGENT_STARTUP.md unchanged.
   Test: agent-startup-context.test.sh: every stub names a heading
8. D8 Root CLAUDE.md of the host's generic rules; a short AGENTS.md points at it.
   Test: scripts/rules-audit.sh --repo . (CI's rules-audit step)
9. D9 hooks.json via run-hook.sh, timeout 30, host events: brief-freshness-gate PostToolUse Edit|Write|MultiEdit; phase-queue-stop Stop; main-script-card, peer-code-sync join the matcher-less SessionStart entry (host `*`), compact-readback a new `compact|clear` one; main-background-only, bash-write-rules PreToolUse Bash.
   Test: compact-readback.test.sh: wired at compact|clear
10. D10 Main gate: main-background-only, main-script-card, peer-code-sync and C3's main parts act only in main's checkout (git-dir is common-dir) with pp_is_main_pane 0 (1-3: not main), after their cheap match.
    Test: main-background-only.test.sh: a linked session is never rewritten; an unknown coordinator is not main
11. D11 brief-freshness-gate keeps the citation and Timed-checks checks; drops the Split arm (no writer), --check, validate_acceptance; cites hooks, templates, config, skills, ci, docs.
    Test: brief-freshness-gate.test.sh: no Environment line, no warning
12. D12 Plugin scripts' linked-worktree commits set COMMANDECK_ALLOW_AGENT_GIT=1 (builder-launch.sh gains it); a linked rebase fires no commit hook (git 2.55.0, 2026-11-03).
    Test: githooks-pre-commit.test.sh: the override lets it through
13. D13 Fast lane: only `<W>/Fast-lane` commits; W is COMMANDECK_WORKSPACES if the worktree's real parent, else `$HOME/orca/workspaces/<main basename>`; pre-push refuses it.
    Test: githooks-pre-commit.test.sh: a stray workspaces value keeps the default lane
14. D15 Owner Q3: C2's 7 helper scripts kept.
    Test: commit-hook-edits-untracked.test.sh: an untracked file is never committed
15. D16 compact-readback takes a checkpoint when `<sid>.md.delivered` is newer; prints at most 9,000 bytes and a pointer.
    Test: compact-readback.test.sh: a delivered checkpoint sets no mark
16. D17 main-background-only leaves what bash-guardrails.sh or no-poll-loops.sh rewrite or refuse.
    Test: main-background-only.test.sh: a bare inbox check is left alone
17. D18 Done messages: `to-main.sh question <subject> <body>`; exit 0 or 3 (queued) writes `.read`; 1 (lost) leaves the job unread for `wait`.
    Test: long-job.test.sh: a refused message stays unread
18. D19 Peer: COMMANDECK_PEER_REPO (`<ssh host>:<path>`); unset, origin only.
    Test: peer-code-sync.test.sh: no peer and dead origin exit 0
19. D20 Copies run plugin scripts from their own folder, project files from the caller's git top; relay unit: main's basename.
    Test: plan-status-budget.test.sh: an outside project runs the plugin's ledger
20. D21 Owner Q4 option 1: notes and warnings every install; rewrites and refusals strict only (A6).
    Test: bash-guardrails.test.sh: the default tier gets only the note
21. D23 Owner: compact-readback stands down while ~/.claude/settings.json registers a `*compact-readback.sh` command.
    Test: compact-readback.test.sh: a user-level readback stands it down
22. D25 Long-job arms: `npm test|t|tst`, `npm run test|test:unit|test:coverage`; no test:guards, test:coverage:gate, test-coverage.sh, merge or seat arm (D38).
    Test: bash-guardrails.test.sh: merge and seat runs pass
23. D26 Wait notes main-only (D10), the until-grep hint every pane; it keys on $PP_SCRATCH's default path, names scripts/wait-test-run.sh.
    Test: bash-guardrails.test.sh: a worker pane gets the hint
24. D27 is_test_path gains `test_*.py`, `*_test.py`.
    Test: new-test-count.test.sh: a test_*.py file is counted
25. D28 long-job passes `28G` to hs_cage; wake-on-exit keeps `CAGE=28G`: hs_cage has no default.
    Test: none, a copied constant
26. D30 C3 rewrites to long-job.sh or wake-on-exit.sh (both need Orca) only with ORCA_TERMINAL_HANDLE set, else the note.
    Test: bash-guardrails.test.sh: a main with no Orca gets the note
27. D31 compact-readback's handoff mark (blocks Stop, restarts main): strict, under Orca only; prints every install; /clear prints and keeps ((j)); no `.holds` removal; a taken checkpoint goes once printed.
    Test: compact-readback.test.sh: a default-tier compact sets no mark
28. D32 peer-code-sync stands down, one line, while `<common git dir>/merge-unit-local.state` names a live pid (merge-lock-guard.sh's live()) ((l)).
    Test: peer-code-sync.test.sh: a live merge leaves main unmoved
29. D33 test-skip-only-blocker exits 0 on `*.py` before its JS patterns (`fit(` matches `model.fit(`) ((o)).
    Test: test-skip-only-blocker.test.sh: a model.fit( test passes
30. D34 wake-on-exit reads no run file, sends by `bash <own folder>/to-main.sh question` from the caller's git top (0 or 3 stamps the dedupe; 1 refused); its pane check stays.
    Test: wake-on-exit.test.sh: the wake goes through to-main
31. D35 CONTRIBUTING.md and pre-push's header: `git config core.hooksPath "$(pwd -P)/.githooks"`, rerun once where relative ((m)).
    Test: githooks-pre-commit.test.sh: an older linked worktree runs main's guard
32. D36 baseline-raise-check WATCHES only `hooks/file-size-cop.sh:CAP`; merge-unit-local runs it after BRANCH is set, `--baseline-raise "<reason>"` passes; no file, no refusal ((n)).
    Test: merge-unit-local-baseline-raise.test.sh: a loosening unit needs the flag
33. D22, D37-D39, D44, D47 Owner: Q5 (a)-(g); Q-A O1, (h) in every user's CLAUDE.md; Q-B O1, merge and seat as today, (i) not built; Q-C O1, `"3 3"` to `"5 5"`; Q-D O1 (j)-(n); Q-E O1 (o), (p); Q-G O1 (q), (r).
    Test: agent-startup-context.test.sh: every stub names a heading
34. D40 Owner Q-F: the evidence rule copied whole, plus the re-read note (## Rule text).
    Test: none, rule text
35. D41 pp_orca_full copied into scripts/paths.sh: poll-agents' drain calls it; a concise check exits 2, consumed rows on stderr.
    Test: poll-agents.test.sh: concise check exits 2 loud
36. D42 repeat-report reads `${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}` (pp_project): ruling-log.sh's file.
    Test: repeat-report.test.sh: an unset log path reads the project's log
37. D43 QUICK_SCRIPTS keeps decision, read-verdict, long-job, checkpoint-context.py, orca-wait, board, answer-worker, state-snapshot, peek, each tested (Test edits); drops send-to-pane.sh.
    Test: main-background-only.test.sh: a measured-quick script passes
38. D45, D46 main-background-only backgrounds main's merge-unit-local.sh and seat.sh run (no guardrails arm, D38), both still detach ((r)); its header, refusal and long-job.sh:13 drop the 30 s cap (none set).
    Test: main-background-only.test.sh: one rewrite per call
39. D48 peer-code-sync fetches unlocked; its ancestry loop and ff-only run under `flock -n` on merge-unit-local.lock; busy: D32's line ((t)).
    Test: peer-code-sync.test.sh: a merge that starts mid-fetch leaves main unmoved
40. D49 Copied `# ponytail:` tags become plain comments (global-rules.md:67).
    Test: none, comment wording

## Not copied

- Plugin does the job (D2): tier1-stop (needs npm; stop-checks.sh, run-shell-tests.sh --changed), main-inbox-waiter-stop (main-watch.sh), pane-inbox-drain (start drain), lib/hook-deadline (no hook blocks on failure; per-entry timeouts), lib/context-clear-decision (context-clear-stop.sh), lib/standing-seats (project.sh), G7 routing keys (seat.sh: maxBuilders, reviewer-floor high; reviewLoop newTestCap; rest unread), plan-close (plan-worktree-close.sh), red-proof (break-run.sh), sync-main (pp_sync_main; its failed-fetch refusal kept), the bare inbox rewrite (no-poll-loops.sh), orca-banner-peek (cos-own-echo.sh).
- Host-only input or no reader (D2b): record-review-convergence (deploy gate); review-findings (fills a per-round count the plugin's ledger keeps null by design); comment-audit (its marker grep flags 4 lines in the guards that ban the markers, and its name grep, run as `git grep -P`, 1,271 lines of hooks and scripts, so it fails on a clean tree; host: on demand only); reviewer-value, ledger-audit, ledger-escaped (host ledgers); ship-unit, record-merge (manual PR); chain-run, chain-transfer (production); plan-setting-n1-check (reads a host-only TypeScript tuning file); verify-diff, watch-tests (npm); plan-install (runs settings.json PreToolUse hooks; the plugin's are in hooks.json); live-drift (reads the host-only live-links.json); rule-drift.py and .json (host rules vs a plugin checkout); codex-long-poll (0 write_stdin logged, 2026-11-03); lib-mutation-note, lib-merge (TypeScript); the host shell-write guard (inline-write note); pre-push's CONVERGED, contract, fast set; pre-commit's protected files, rule-drift; review-results and chain-runs metrics.
- Rules the plugin has (C1): planning freshness, integration surface, no-backward-compat, comment rules (global-rules); smallest change, reconcile, no detached launch, compact (AGENT_STARTUP); test-encodes-why, bug-fix-first, never-weaken (test-rules); names-its-bug, rerun-a-timeout (brief).

## Accepted failure modes

1. await-agents and watch-agents ship with no test: the host has none and the order is a copy.
   Test: none, the host carries no test for them
2. The phase queue works only when the session writes it; the plugin's one prompt for that is the global-rules line C1 adds.
   Test: phase-queue-stop.test.sh: an open box refuses Stop
3. Queue ownership is the host's first-observer rule, copied as is: the first session to Stop after the queue is written adopts it, so an unrelated session that stops first is held and the instructed one then passes, until the queue is rewritten.
   Test: phase-queue-stop.test.sh: the first Stop adopts the queue

## Assumptions

- A1 Host main moved after the gap report (963f5989d vs 0c01c20ca). Builder check before C1: `git -C <host> log --oneline 963f5989d..main -- <each source file>`; empty: copy as planned; not empty: copy the newer text and log it in Plan change log.
- A2 No plugin script runs git under a headless `claude -p`: settled, `rg -n "claude (-p|--print)" scripts hooks` 2026-11-03 finds comments only.
- A3 Linked-worktree commits in plugin scripts: settled 2026-11-03 by `rg -n 'git (-C "?\$[A-Z_]+"? )?(commit|rebase|merge|push)\b' scripts/*.sh`: builder-codex-pass.sh:1912 has the override, builder-launch.sh:448 gains it (D12), the rebases need none (D12), the merge-unit-local and builder-launch:248 commits run in the main checkout.
- A4 Carried labels may differ from the Break labels; the Builder renames the check to the Break's words, never weakens it.
- A5 Commit messages: `git log -500 --format=%B`, 2026-11-03, shows 0 lines the copied commit-msg would refuse (home path or .local host) and 0 Claude trailers.
- A6 Hook tier: settled by the owner (Q4 option 1, 2026-11-03): notes and warnings every install, rewrites and refusals strict only. brief-freshness-gate, main-script-card, bash-write-rules stay ungated; main-background-only, phase-queue-stop, peer-code-sync and compact-readback (its handoff touch only, D31) call pp_strict and join the STRICT list; bash-guardrails.sh: wait notes inside the main gate, the until-grep hint after it closes (every pane, D26), both above pp_strict; the rewrites below it.
- A7 Python skips on the shared test-path predicate: settled 2026-11-03 by piping a Write of `pytest.skip("x")` and of `@unittest.skip("x")` on `/x/tests/rows.test.py` to `COMMANDECK_HOOK_TIER=strict bash hooks/test-skip-only-blocker.sh`: rc=0 both (D27); its `fit(` arm matches `model.fit(`, so D33 exits on `*.py`.
- A8 The plugin registers no compact-readback through settings.json: settled 2026-11-03, `rg -n compact-readback scripts/setup.sh hooks/hooks.json` finds nothing, so D23's check never matches the plugin's own entry.
- A9 Ledger workspaces: settled 2026-11-03, paths.sh with `COMMANDECK_WORKSPACES=/fixture/ws`: this linked worktree gives the real folder; a mktemp -d `git init` checkout, CLAUDE_PROJECT_DIR unset, `/fixture/ws`.

## Steps

- new {CLAUDE.md,AGENTS.md} -- G1
- modify templates/{global-rules.md,rules-details.md} -- G6
- new skills/file-issue/SKILL.md -- G10
- new scripts/{long-job,plan-status,await-agents,poll-agents,watch-agents,wake-on-exit,token-ledger,memory-flush,commit-hook-edits,baseline-raise-check}.sh -- G9
- new scripts/__tests__/{long-job,plan-status-budget,poll-agents,wake-on-exit,token-ledger,memory-flush,commit-hook-edits-untracked,ledger-codex-turn-usage.refute,ledger-missing-usage.refute,budget-context-metric.refute,baseline-raise-check,merge-unit-local-baseline-raise}.test.sh -- G9
- new scripts/__tests__/fixtures/{token-ledger,orca-1.4.246-views.json} -- G9 (D6)
- modify scripts/merge-unit-local.sh ~234 -- G9 (D36)
- modify scripts/paths.sh -- G9 (D41)
- modify hooks/{lib/test-path.sh,test-skip-only-blocker.sh} -- G4 (D27, D33)
- modify hooks/bash-guardrails.sh -- G5
- modify hooks/__tests__/{bash-guardrails,test-skip-only-blocker}.test.sh -- G5, G4
- modify scripts/{new-test-count.sh,__tests__/new-test-count.test.sh} -- G4
- modify hooks/__tests__/agent-startup-context.test.sh -- G6 (D39)
- new hooks/{brief-freshness-gate,compact-readback,phase-queue-stop,main-background-only,main-script-card,bash-write-rules,peer-code-sync}.sh -- G8
- new hooks/__tests__/{brief-freshness-gate,compact-readback,phase-queue-stop,main-background-only,main-script-card,bash-write-rules,peer-code-sync}.test.sh -- G8
- modify hooks/hooks.json -- G8 wiring
- modify hooks/__tests__/hook-tier.test.sh -- G8 (A6)
- modify hooks/__tests__/setup-gate.test.sh -- G8 (Q-I)
- new scripts/repeat-report.sh -- G3
- new scripts/__tests__/repeat-report.test.sh -- G3
- new .githooks/{lib-agent-guard.sh,commit-msg,pre-commit} -- G2
- modify .githooks/pre-push -- G2
- modify scripts/builder-launch.sh ~448 -- G2 (D12)
- new hooks/__tests__/{githooks-commit-msg,githooks-pre-commit,githooks-pre-push}.test.sh -- G2
- modify {CHANGELOG.md,.claude-plugin/plugin.json,README.md,CONTRIBUTING.md} -- release

## Cuts

Build order: C1, C2, C3, C4, C5, C6, C8, C7; C2, C5 after Q-H and Q-I, C6 after Q-I; builder-codex-pass.sh commits every cut, never by hand; build commits run main's .githooks (wired absolute), guarded only after the merge.
- Bug named: a one-line comment per check names its bug.
- Copy rule: copy the host text; change only what D6, D16-D49, the ## fits sections and each cut's Drops and Maps name; skip what the plugin has.

### C1 rules text (G1, G6, G10), ~160 lines
- Produces: root CLAUDE.md (host intro, subagent-model line), 5-line AGENTS.md; ## Rule text (D7, D40; global-rules about 173 of 200 lines); the stub-count edit (D39); skills/file-issue (rewrite, ask on material gaps, file only when told, report the URL).
- Drops: host CLAUDE.md product, CLI, data, fallback, deploy, flag, repo-guard, delta, review-loop parts; rule lines ## Rule text does not name; paved-road's registry; file-issue's surfaces, labels, milestones, twin, board, owners.
- Consumes: none. Consumers: setup.sh merges global-rules.md into users' CLAUDE.md; agent-startup-context.test.sh's stub count (D39).
- Checks: global-rules.md under 200 lines; startup-size.sh, ci/leak-test.sh pass.

### C2 scripts (G9), ~2945 lines
- Produces: 10 scripts, 12 tests, token-ledger fixtures, poll-agents' views fixture (`_about`, `check.full`, `check.concise` only; names, paths neutral); long-job.sh, wake-on-exit.sh (C3, C5); the `--baseline-raise` step (D36); pp_orca_full (D41).
- Consumes: paths.sh PP_*, to-main.sh (D18, D34), hs_cage, pane-budget-gate.sh (refute test), file-size-cop.sh's `CAP=`.
- Drops: long-job's run-id comment, host example, header's 30 s clause (D46) and `board.sh prints it`; wake-on-exit's host example, repo name, run file, orca-ide send (D34); token-ledger's branch prefix; owner lines (commit-hook-edits, await-agents, watch-agents); baseline-raise-check's baselines, floor, branches, cases (D36).
- Maps (D20): watch-agents in the caller's git top, poller from its folder; plan-status's ledger, long-job's `wait with:` name their folder; `.claude/hooks/` to `hooks/`; commit-hook-edits' worktree to `$PP_WORKSPACES/<unit>`; poll-agents' main checkout to `$PP_MAIN` (exported), fixture to `scripts/__tests__/fixtures/`, scratch env COMMANDECK_SCRATCH; token-ledger's briefs to `$PP_MAIN/.claude/briefs`, plans and rates the caller's git top; plan-status' miss log to `~/.commandeck/plan-status`.
- Consumers: merge-unit-local.sh's usage, merge-unit-local.test.sh (old flags unchanged); pp_orca_full and the rest are new.
Break: scripts/__tests__/long-job.test.sh -- a second start fails -- scripts/long-job.sh name lock
Break: scripts/__tests__/long-job.test.sh -- a refused message stays unread -- scripts/long-job.sh .read write
Break: scripts/__tests__/commit-hook-edits-untracked.test.sh -- an untracked file is never committed -- scripts/commit-hook-edits.sh tracked filter
Break: scripts/__tests__/wake-on-exit.test.sh -- the wake goes through to-main -- scripts/wake-on-exit.sh send
Break: scripts/__tests__/merge-unit-local-baseline-raise.test.sh -- a loosening unit needs the flag -- scripts/merge-unit-local.sh check_baseline_raise
Break: scripts/__tests__/poll-agents.test.sh -- concise check exits 2 loud -- scripts/paths.sh pp_orca_full
Bad input: empty or non-JSON text: pp_orca_full returns 0, no rows; only a concise reply exits 2.

### C3 bash guardrails (G5), ~475 lines
- Produces: lone_call, rewrite_call, SEG arrays, strip_prefix, seg_head; tail -f and compound gh run watch notes; lone gh run watch to wake-on-exit, D25 suite runs to long-job, under Orca only (D30); foreground `long-job.sh wait` backgrounded; the until-grep hint (D26); via allow_json, per A6.
- Already in the plugin: bare inbox rewrite (no-poll-loops.sh), here-doc end word, raw pane read, kill guard, search_bounded, whole-repo message; no merge or seat arm (D38).
- Drops: AWS fence, local-checks arm, serena-down marker, caller hunt, shell-write guard, host folder, npm, scratch names; host :1288's board.sh becomes `long-job.sh list`.
- Consumes: C2's long-job.sh and wake-on-exit.sh; pp_is_main_pane and the checkout test (D10).
Break: hooks/__tests__/bash-guardrails.test.sh -- tail -f into grep gets a note -- hooks/bash-guardrails.sh wake
Break: hooks/__tests__/bash-guardrails.test.sh -- a lone gh run watch is rewritten -- hooks/bash-guardrails.sh gh rewrite
Break: hooks/__tests__/bash-guardrails.test.sh -- a linked suite run is not rewritten -- hooks/bash-guardrails.sh main gate
Break: hooks/__tests__/bash-guardrails.test.sh -- a worker pane gets no wait note -- hooks/bash-guardrails.sh note gate
Break: hooks/__tests__/bash-guardrails.test.sh -- a main with no Orca gets the note -- hooks/bash-guardrails.sh Orca

### C4 new-test-count (G4), ~392 lines
- Produces: Python reader; TypeScript reader, regex fallback; moved, renamed count as new; .each once; `test.skip(cond, 'why')` gates not counted, `test.skip('case', fn)` counted; the issue-433 edit; D27; D33.
- Drops: --unit ceiling output, tooling cap, subject growth.
- Consumes: is_test_path; the project's typescript when present.
- Consumers (unchanged, D4): builder-codex-pass.sh:1633-1640, :770 (--edited), builder-codex-pass-try.test.sh, new-test-count.test.sh; test-skip-only-blocker.sh:34 (D33).
Break: scripts/__tests__/new-test-count.test.sh -- a test_*.py file is counted -- hooks/lib/test-path.sh Python name arm
Break: hooks/__tests__/test-skip-only-blocker.test.sh -- a model.fit( test passes -- hooks/test-skip-only-blocker.sh `*.py` exit
Bad input: an empty diff or absent file list: line 1 is 0, exit 0 (new-test-count.test.sh).

### C5 hooks (G8), ~1632 lines
- Produces: 7 hooks, 7 tests, hooks.json entries (D9), the tier list (A6); D10, D11, D23, D31, D32, D45, D48; the phase-queue owner folder.
- Drops: brief-freshness-gate's parts per D11; compact-readback's `.holds` line; main-script-card's main-session half, unshipped names; main-background-only's send-to-pane.sh (D43), 30 s wording (D46), test-coverage row; peer-code-sync's peer-runtime.sh, peer path, main-watch restart; bash-write-rules' banner arm; phase-queue-stop's test command.
- Maps (D20): bash-write-rules' rules folder (Data design).
- Consumes: run-hook.sh, hook-fire-log.sh, pp_is_main_pane, pp_strict, no-poll-loops.sh, bash-guardrails.sh (D17), .delivered (D16), merge-unit-local.state and .lock (D32, D48).
- Consumers: hook-tier.test.sh's STRICT list, +4 (A6); setup-gate.test.sh:35's count (Q-I); context-clear-stop.sh, context-line.sh read the handoff mark (D31); merge-unit-local.sh (D48).
Break: hooks/__tests__/phase-queue-stop.test.sh -- an open box refuses Stop -- hooks/phase-queue-stop.sh open-box
Break: hooks/__tests__/phase-queue-stop.test.sh -- a later visitor is not held -- hooks/phase-queue-stop.sh owner
Break: hooks/__tests__/compact-readback.test.sh -- a user-level readback stands it down -- hooks/compact-readback.sh stand-down
Break: hooks/__tests__/main-background-only.test.sh -- a linked session is never rewritten -- hooks/main-background-only.sh checkout gate
Break: hooks/__tests__/main-background-only.test.sh -- a bare inbox check is left alone -- hooks/main-background-only.sh ask
Break: hooks/__tests__/main-background-only.test.sh -- an unknown coordinator is not main -- hooks/main-background-only.sh pane gate
Break: hooks/__tests__/compact-readback.test.sh -- a clear sets no mark -- hooks/compact-readback.sh source
Break: hooks/__tests__/compact-readback.test.sh -- a delivered checkpoint sets no mark -- hooks/compact-readback.sh delivered
Break: hooks/__tests__/peer-code-sync.test.sh -- a main ahead is never moved -- hooks/peer-code-sync.sh fast-forward
Break: hooks/__tests__/peer-code-sync.test.sh -- a live merge leaves main unmoved -- hooks/peer-code-sync.sh merge
Break: hooks/__tests__/peer-code-sync.test.sh -- a merge that starts mid-fetch leaves main unmoved -- hooks/peer-code-sync.sh lock
Break: hooks/__tests__/compact-readback.test.sh -- a default-tier compact sets no mark -- hooks/compact-readback.sh tier
Break: hooks/__tests__/bash-write-rules.test.sh -- a rule-glob write shows the rule once -- hooks/bash-write-rules.sh mark
Break: hooks/__tests__/bash-write-rules.test.sh -- another project gets its own rule -- hooks/bash-write-rules.sh rules folder

### C6 repeat-report (G3), ~170 lines
- Produces: repeat-report.sh and test; ruling topics kept; hook-block pattern `run-hook.sh hooks/<name>.sh`.
- Maps: the ruling log to ruling-log.sh's (D42).
- Consumes: PP_MAIN, PP_MAIN_SLUG, PP_SCRATCH, PP_WORKSPACES, pp_project; GNU `date -d` (requirements.sh's PATH).

### C8 githooks (G2), ~798 lines
- Produces: lib-agent-guard (topology, Fast lane, headless ancestry); commit-msg (trailer strip, home-path, .local refusal); pre-commit (ancestry, then override, Fast lane or topology); pre-push's ancestry, topology guards, COMMANDECK_ALLOW_WORKTREE_PUSH; D12; D35.
- Drops: lib-merge, lib-mutation-note (D2b), protected files, rule-drift, pre-push CONVERGED, contract, fast set; commit-msg's GNU `sed -i` to a temp-file write.
- Consumes: git, ps; no paths.sh (hooks source only .githooks libs); lib-agent-guard computes the lane (D13).
- Consumers: ci-pre-push.test.sh (absolute hooksPath, passes); relative checkouts (D35); merge-unit-local.test.sh, duplicate-agent-guard.test.sh (null hooksPath); fast-lane.sh's commit (D13).
Break: hooks/__tests__/githooks-pre-commit.test.sh -- a bare linked commit is refused -- .githooks/lib-agent-guard.sh topology
Break: hooks/__tests__/githooks-pre-commit.test.sh -- headless -p git is refused -- .githooks/lib-agent-guard.sh ancestry
Break: hooks/__tests__/githooks-pre-commit.test.sh -- only the canonical Fast lane commits -- .githooks/lib-agent-guard.sh lane path
Break: hooks/__tests__/githooks-pre-commit.test.sh -- a stray workspaces value keeps the default lane -- .githooks/lib-agent-guard.sh workspaces
Bad input: COMMANDECK_WORKSPACES unset, empty, `/`-ended or not the real parent: default lane; an empty or comment-only message: left to git (githooks-commit-msg.test.sh).
Break: hooks/__tests__/githooks-commit-msg.test.sh -- a home-path message is refused -- .githooks/commit-msg home-path
Break: hooks/__tests__/githooks-commit-msg.test.sh -- Claude trailers are stripped -- .githooks/commit-msg trailer strip
Break: hooks/__tests__/githooks-pre-push.test.sh -- a linked push is refused -- .githooks/pre-push topology call
Break: hooks/__tests__/githooks-pre-push.test.sh -- headless -p is refused with the override -- .githooks/pre-push ancestry call

### C7 release (all), ~45 lines
- Consumes: C1-C6, C8.
- Produces: CHANGELOG.md section (house style), version bump, README, CONTRIBUTING lines.

## Rule text

- global-rules.md `## Agents and tokens` gains these five lines exactly as written here (D37, (h)); source and change per line:
- `If you must wait, wait once, blocking. Never poll: each poll is a full round trip that returns "still running".` (host token-efficiency.md:87-88, word for word)
- `One question over many files is a SCRIPT, not a sweep of reads: compute the answer and keep only the answer.` (:62-63's first sentence, word for word)
- `Evidence is never filtered to save tokens. On a red result, a truncated output or any doubt, read the raw output. Re-read a file after a change, after another writer touched it, or whenever you are unsure. Savings come from avoiding repetition, never from looking less carefully. (The re-read is for a file another writer touched or one you are unsure of, never to confirm your own edit.)` (:95-98 word for word, then the owner's note, D40)
- `Tag each claim [verified] (you ran or read it), [likely] (inferred, not run) or [uncertain]; "I did not check X" is useful.` (host CLAUDE.md:131)
- `With strict hooks on: when the owner says to work through all phases, write .claude/phase-queue.md first, one "- [ ]" box per item, and tick each "[x]" as it lands green; Stop is refused while a box is open.` (new wording of what phase-queue-stop.sh:17-25 enforces; the host has no rules line for it)
- Stubs: `Details, ~/.commandeck/plugin/templates/rules-details.md, Token efficiency.` and the same for `Tests and comments.` (D39)
## Rules-details text

- rules-details `## Token efficiency`, word for word: host token-efficiency.md:8-12, 16-19 (ending at "throwaway scripts."; :19's hook sentence cut), 27-35, 39-53, 57-61, 74-76 (startup files change only between batches, (q)), 77-81, 89-91.
- rules-details `## Tests and comments`, determinism ((p)), as three lines: `Never assert on wall-clock timing. Mock timers, and restore them in a teardown hook.` (tests.md:265-267, vitest, node:test calls and folder names cut); `A process-wide mock retains call args: restore it in a teardown hook, and never push into an unbounded array from inside a mock.` (:268-270, `mock.method` and `t.after` cut); :271-273 word for word.
- Then tests.md:316-324 word for word (public interfaces, one test per behaviour, no trivial tests, no mock-only assertion); :251-253 with its lead word `Dropped:` as `Not run:` (it named the host's closing-run list, :246-250, not copied); :258-260 with `scripts/host-services.sh` for the host path and `(#2524)` cut.
- Then comments.md:11-18 and :28-40 word for word except: the `##` headings at :11 and :28 become `###`, so both stay inside `## Tests and comments`; :32-33 ends at "explains a current constraint." (the `docs/lessons/` clause cut); :36-37 reads `Hook-enforced: hooks/edit-content-tripwires.sh.` (the commit-trailer pointer cut); :40 ends at `(TODO(#123): ...).` (the observation-issue gate cut); :15 ends at `no tag.` (`(see the next section)` cut: that section, :21-26, is not copied, and the ban lives at global-rules.md:67); :18 ends at `if you do.`; :19, :21-26 and :42-47 are host-only.

## Test edits

- scripts/__tests__/new-test-count.test.sh:25 "a check moved with the same label is not new (issue 433)" becomes "a moved test counts as new", expecting 1: approved by the owner, Q2 (D5).
- hooks/__tests__/hook-tier.test.sh:14-16 STRICT list gains main-background-only, phase-queue-stop, peer-code-sync and compact-readback (owner Q4, A6; bash-guardrails, also gated in part, is listed today); the check itself is unchanged.
- hooks/__tests__/agent-startup-context.test.sh:188 "every Details stub names a section that exists in rules-details.md" expects `"5 5"` in place of `"3 3"` for the two new stubs; it still checks every stub's destination. Approved by the owner (D39): a test edit that follows the change.
- scripts/__tests__/wake-on-exit.test.sh (carried): routing and receipt edits in ## Wake-on-exit fit; every other carried test in ## Carried test fits, ## Githooks test fits.
- scripts/__tests__/merge-unit-local-baseline-raise.test.sh (carried): cases 1-4 run on a `hooks/file-size-cop.sh` fixture, `CAP=400` raised to `CAP=401`; case 1 expects `LOOSENED hooks/file-size-cop.sh CAP #1: 400 -> 401`; the floor cases (5 on) go with the floor (D36); reason strings name no one.
- hooks/__tests__/brief-freshness-gate.test.sh (carried): its 3 Split cases go with the arm (D11); the template case counts the Timed-checks warning only; host :92-279's 19 validate_acceptance labels go with D11.
- hooks/__tests__/setup-gate.test.sh:35 "every registered hook was run": 58 -> 65 for D9's 7 entries, its other checks unchanged (Q-I).
- hooks/__tests__/main-background-only.test.sh (carried): host :14 checked the exit code only, which a rewrite or a linked checkout also gives; "a measured-quick script passes" runs each of D43's 9 kept names through `rewrote` in $ROOT, main's pane pinned, and expects 9 empty outputs (one check, joined), so dropping any name fails (D43).
## Carried tests

- hooks/__tests__/main-script-card.test.sh (new; host agent-startup-context.test.sh:74-94, :333): no card in worker or reviewer panes; one usage line each for peek, seat, merge-unit-local, long-job; seat launch and collect; at most 40 lines; failing or 30 s --help, under 12 s (stubs peek.sh OK, merge-unit-local.sh BAD, seat.sh SLOW: "1 0 0"); under 10,240 bytes; :53-73 go (C5). The card reads `$PLUGIN/scripts/<name>.sh` from its own folder (D20; host :12, :34 read CLAUDE_PROJECT_DIR), so the stub case copies hooks/main-script-card.sh and hooks/lib/ into a scratch plugin tree `$FAKE/hooks/`, the three stubs into `$FAKE/scripts/`, and runs `$FAKE/hooks/main-script-card.sh` from main's checkout; no CLAUDE_PROJECT_DIR and no new env knob.
- hooks/__tests__/main-background-only.test.sh: both_check (host :67-83) names each owner: npm test, gh run watch: bash-guardrails (strict, under Orca); seat.sh run, merge-unit-local.sh: main-background-only (D45); `bash -c 'npm test'`: the note (D3), then main-background-only; test-coverage.sh row goes. New: run-list fails, not main.
- Pane pin, every D10-gated case: an orca-ide stub first on PATH (as context-clear-stop.test.sh:28-43), COMMANDECK_RUN=run-t, run-list naming the case's handle as coordinator; worker: another handle; no Orca: handle unset.
- hooks/__tests__/peer-code-sync.test.sh (+1): a background `flock` holds merge-unit-local.lock, no state file, origin ahead: D32's line, main unmoved (D48).
- scripts/__tests__/poll-agents.test.sh: ORCA_VIEWS reads the sanitized fixture (C2).
- scripts/__tests__/{token-ledger,ledger-codex-turn-usage.refute,ledger-missing-usage.refute}.test.sh: the ledger runs in `$BOX/main` (`git init -q`, mktemp -d; Python: `cwd=`), CLAUDE_PROJECT_DIR unset, `/fixture/ws`, fixtures and asserts kept (A9); plan-status-budget's host cases (no value): unchanged.

## Wake-on-exit fit

- Copy (D34): `R=$(bash "$HERE/to-main.sh" question "$SUBJECT" "$BODY" 2>&1)`; 0 posted, 3 queued (both stamp), else refused; `pp_wake_log wake-on-exit main "$LABEL" "$WL"` plus `${R:0:200}` unless posted; relay unit `${PP_MAIN##*/}`.
- Tree: `cp -R "$ROOT/scripts" "$FAKE/"`, SCRIPT in it; stub to-main.sh logs `SEND`, `$*`, `pwd -P` to $WAKE_TEST_{SENDS,BODY,CWD}, exits ${WAKE_TEST_TOMAIN_RC:-0}, on 1 printing `consumer_fenced` to stderr; stub cos-tell.sh logs `$*` to $RELAY_LOG, exits ${RELAY_RC:-0}.
- Setup: CLAUDE_PROJECT_DIR unset; no current-run seed (host :19-20); every call runs from `$SCRATCH/proj` (`git init -q`); orca-ide stub: `terminal list` only; COMMANDECK_ names; wake log `$SCRATCH/wake-log.jsonl`, field `.to`.
- Successful (host :111-120): one SEND; BODY's line 1 starts `question failing: FAILED exit 7`; CWD is `$SCRATCH/proj` (pwd -P); the row reads `posted failing main`.
- Refused (host :338, :344): both env knobs become WAKE_TEST_TOMAIN_RC=1; `refused true` and both no-stamp checks kept.
- Queued (new, "a queued wake is stamped once", after host :347): WAKE_TEST_TOMAIN_RC=3, `held -- bash -c 'exit 8'` twice: one SEND, last row `queued held main`, `wake-last-held-8` written, the second send log `deduped:`.
- Deduplicated (host :325-336): unchanged.
- Run file: host :154-158's refusal goes; after :166, "a launch needs no run file": HOME=$SCRATCH/empty-home exits 0, one new SEND.
- Env forward (host :96-100): COMMANDECK_WORKSPACES=/srv/ws; COMMANDECK_SCRATCH forwarded, COMMANDECK_WAKE_LAUNCHER not; the set is `^(ORCA_|CODEX_HOME=|COMMANDECK_(MAIN|WORKSPACES|SCRATCH)=)`.
- Relay (host :380-401): `$SCRATCH/current-run` holds `run_t`; $RELAY_LOG has `--note FYI event: proj push fail abc123def456 exit 1`, then `... push ok abc123def457 exit 0`; RELAY_RC=1 keeps one SEND; plainjob logs none.
- Builder: green before C2's commit; a red check is fixed in the copy, never dropped.

## Carried test fits

- Sweep, 2026-11-03: each carried host test grepped for `current-run|\.config/orca|board|send-to-pane|main-watch|\.claude/(config|hooks/__tests__/lib)|HOME/\.claude` and the host's env prefix; one fit per hit; that prefix to COMMANDECK_, `.claude/scripts/` and `.claude/hooks/` to `scripts/`, `hooks/` (D6).
- Tier (A6): main-background-only, phase-queue-stop, peer-code-sync, compact-readback tests export COMMANDECK_HOOK_TIER=strict (bash-guardrails.test.sh:5).
- long-job (D18): to-main.sh sends the done message: the stub's `terminal list` main row is what pp_pane_of finds; ok:true gives 0, sendrefuse 1, no mainpane 3 (queued); host :51-53 (routing.json) and :57-60 (case-filter.sh, absent here) go; "the board" cut from :93, :147, :216.
- peer-code-sync: :31's main-watch.sh, :50 and :79-88 (restart, 5 checks) go; :41 reads `$ROOT/hooks/hooks.json`: `[.hooks.SessionStart[] | select(.matcher == null) | .hooks[].command | select(test("peer-code-sync.sh"))] | length` is 1 (D9).
- compact-readback (D16, D31): ORCA_TERMINAL_HANDLE=term_t, CLAUDE_CONFIG_DIR unset; (c) writes `s1.md.delivered`, s1.md `touch -t 202601010000`; (g) the reverse; (b)'s `.restarted` stays, unread; :56-59 (a ~/.claude/hooks symlink, never installed here) go; new "wired at compact|clear": peer-code-sync's jq, `.matcher == "compact|clear"`, 1.
- main-script-card: new "the card is wired": peer-code-sync's jq for main-script-card.sh, 1.
- repeat-report: CLAUDE_CONFIG_DIR unset ((v); this runner sets it, 2026-11-03).
- baseline-raise-check (D36): fixture at `hooks/file-size-cop.sh`; :46, :47, :50, :80 kept; :41-45, :48-49, :51-79 go.
- No fit beyond names: poll-agents, memory-flush (`--store`), commit-hook-edits-untracked, merge-unit-local-baseline-raise, plan-status-budget, token-ledger, both ledger refutes (TOKEN_LEDGER_CLAUDE_ROOT), brief-freshness-gate, phase-queue-stop, bash-write-rules.

## Githooks test fits

- githooks-pre-commit: :24-58 (protected files, 7) and :186-249 (rule-drift, 13) go; :134's label loses the owner's name: "the agent override permits linked commit".
- githooks-pre-push: keeps check(), the ancestor-driver (:37-53), sha, ZERO, run_role_prepush (:129-148) and :157-188 (14 checks); build_repo keeps git init, the two commits and origin/main; GATE, VERIFY, the push-checks stub, run_prepush, pp, record and :190-498 (review marker, tier, contract, fast set: 52) go; the role calls drop the local-guards skip: the plugin's pre-push passes the zero (deleted) sha they push.
- githooks-commit-msg: :106's `/tmp/<host>/x` becomes `/tmp/proj/x` (leak word).

## Fixture maps

- hooks/__tests__/bash-write-rules.test.sh: cases run in a scratch git checkout $FX (host :89-98; its .claude/rules, D20); banner arm and :89's banner key go, rules sort by name: zz-a-code.md (`src/**`, `lambdas/**`, `shared/**`; `# Code rules`, `# Security notes`; 3,000 chars) for backend.md; zz-b-tests.md (`**/__tests__/**`; `# Test Standards`, `## Running tests`; 7,500) for tests.md; zz-c-comments.md (`**/*.ts`; `# Code comments`; 4,000) for comments.md; zz-big.md as :92. Only code plus comments fit 10,000, so :36-47, :80-83 hold; :29, :69, :73 expect `matches .claude/rules/zz-a-code.md`; :30, :42 go; :122's floor is `-eq 6`.
- bash-write-rules heading map (each check keeps its `has` of the injected text, its expected value and its session): `# API and Data Conventions` becomes `# Code rules` at host :31, :65, :66, :70, :74, :76, :81, :85, :127, :129 (both calls), :131; `# Security Review Policy` becomes `# Security notes` at :32, :71, :75; `# Test Standards`, `## Running tests`, `# Code comments` stay (zz-b-tests.md and zz-c-comments.md carry them).
- bash-write-rules paths: the hook's marks live in $PP_SCRATCH (Data design), so the test sets `COMMANDECK_SCRATCH=$(mktemp -d)` and its one trap (host :12, :89) removes that folder and $FX in place of `/tmp/claude-bash-rules-*`; :61's outside-the-checkout target `/tmp/<host>/zz-bwr.json` becomes `$COMMANDECK_SCRATCH/zz-bwr.json` (leak word, D6); :90-91's hook and lib copy goes: every case pipes to the plugin's own `$ROOT/hooks/bash-write-rules.sh` from cwd $FX, payload .cwd $FX (ctx's `$ROOT` too) .
- host :76's `$ROOT/src/zz-bwr-scratch.ts` and :107's `"$ROOT/.claude/rules"` take `$FX` (:122 counts its 6 globs).
- "another project gets its own rule" (one check, `"yes no"`): a second scratch checkout $FX2 holds zz-other.md (`notes/**`; `# Other rules`); `echo x > notes/a.md` from $FX2 injects `# Other rules`, the same write from $FX injects none.

## Guard fits

- Basis: every repo-wide guard test stays green but setup-gate's count (Q-I); run 2026-11-03 on this checkout plus raw copies wired per D9; each cut reruns them.
- help.test.sh:16-24: plan-status, await-agents, poll-agents, watch-agents, token-ledger, memory-flush, commit-hook-edits, baseline-raise-check get `case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac` (answer-worker.sh:46 less `head`: await-agents' line 2 is `#`) after `set -…`, before any source, write, call ((u)).
- project-main.test.sh:95: long-job :63 `rm -rf "$A"` -> `pp_rm_rf "$A"` (paths.sh:27, via codex-helpers.sh:58), `exit 0` stays.
- hook-fire-log-summary.test.sh:52-65: phase-queue-stop :123 -> `queue_check || { HOOK_FIRE_REASON=phase-queue-open; exit 2; }` ((w)); main-background-only :77 a note (D3: additionalContext, advise, exit 0); brief-freshness-gate :99, :104 go with --check (D11).
- plugin.test.sh:241: repeat-report :28, memory-flush :16, token-ledger :27 and D23 read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` (paths.sh:1094) ((v)); RE291 (:239) skips token-ledger's Python.
- run-hook.test.sh:38 (Bash 3.2 `-n`): bash-write-rules' `OUT=$(python3 … <<'PY' … PY)` (:18-132) -> `rules_py() { python3 -I - "$@" <<'PY' … PY }`, `OUT=$(rules_py …)` (duplicate-agent-guard.sh:53); commit-hook-edits :35's patterns `(`-led; both parse.
- hook-retire-when.guard.test.sh:18, `# Retire when:` brief-freshness-gate `a linter checks every path a brief cites`; compact-readback `Claude Code re-reads the checkpoint after a compact`; main-background-only `Claude Code backgrounds slow main calls`; bash-write-rules `Claude Code applies .claude/rules globs to Bash writes`.
- blocked-texts.guard.test.sh: phase-queue-stop :114's example line in backticks.
- codex-parity.guard.test.sh:27: new hooks, scripts, githooks 100755.
- setup-gate.test.sh:35: 58 -> 65 (Q-I); context-overhead 10,325 of 16,417 B.
- Bad input: none, only a first -h or --help matches.

## Refute fixtures

- budget-context-metric.refute: the host's gate runs in a main checkout, where pane-budget-gate.sh:112 exits 0 (:96 too, off strict), so it cannot fail. plan-status init and budget still run in `$BOX/u1` (`git init`, A9); then u1's `.claude` (brief, status) is committed and `git -C $BOX/u1 worktree add -q $BOX/wt/u1` makes a linked pane named u1 (its brief is `<unit>.md`, pane-budget.sh:20); the gate runs with CLAUDE_PROJECT_DIR=$BOX/wt/u1, COMMANDECK_HOOK_TIER=strict, no session_id, as the host's (one runs the gate's Serena check, pane-budget-gate.sh:158). "a measured budget passes a linked pane": PANE_BUDGET_PLAN=p, the host's 999999 config, exit 0. New "a one-token budget refuses a linked pane": PANE_BUDGET_PLAN=none (no status file), config `{"context":1,"compactions":0}`, exit 2.
- Builder check before C2's commit, on that file: control 2 and main 0: kept. Control 0: the fixture still stops early or measures no context; find the line with `bash -x` and fix the fixture, never the gate. Main 2: the ledger's p90 is under the gate's own measure of the same transcript; a finding sent to main, the test unedited.
- plan-status-budget "an outside project runs the plugin's ledger": `$FAKE/scripts/` holds a copy of scripts/plan-status.sh and a token-ledger.sh stub printing the host's three pane rows (u1 tooling 100/0, u2 tooling 200/1, u3 runtime 300/2); `$BOX/repo` (`git init`, no plan-status) holds decoys `.claude/scripts/token-ledger.sh` and `scripts/token-ledger.sh` printing the same units at context 999, compactions 9. From cwd `$BOX/repo`, TOKEN_LEDGER_SCRIPT unset, HOME=$BOX/home: `bash $FAKE/scripts/plan-status.sh p init u1 u2 u3`, then `p budget`. Expected `.budget["gate-ci"]` context/compactions p90: `300/2` (a project-side ledger gives `999/9`).

## Approved user-visible changes

- Approved (Q1): main's gh run watch and suite runs rewritten; tail -f into grep: a wait note; main's slow foreground calls backgrounded; Stop refused on an open phase-queue box; readback after a compact; main's start fast-forwards, shows a script card; a rules-glob write shows the rule once; a dead cited path warns; a moved test counts as new; file-issue skill; token rules.
- Kept (r2): inbox rewrite, empty-banner block, divergence and Codex short-poll refusals.
- Approved (Q5, D37), before -> after: (a) new-test count: also Python, nested JS/TS, t.test, .each once, no skip gates; (b) until-grep on a test log: silent -> hint; (c) main's foreground `long-job.sh wait` -> background; (d) a long job ends -> main gets its exit code; (e) .githooks refuse linked commits (Fast lane aside), pushes, headless `claude -p` git, home-path or .local messages, strip Claude trailers; (f) readback cut at 9,000 bytes, off beside a user-level one; (g) start fast-forward from origin, the peer if set; (h) CLAUDE.md: five ## Rule text lines, two pointers; (i) not built (D38).
- Narrowed in r4: no Orca, the note (D30); a default-tier or non-Orca compact, no Stop block or restart (D31); the wake reaches this project's main (D34).
- Approved (Q-D, Q-E, Q-G; D44, D47): (j) /clear: nothing -> checkpoint printed, kept; (k) heavy fixture, no `Timed checks:` line: silent -> one WARN; (l) main starts mid-merge: fast-forward -> skipped, one line; (m) .githooks: relative -> absolute path; (n) raising file-size-cop's CAP: merges -> needs `--baseline-raise`; (o) a Python `model.fit(` test: refused -> allowed; (p) rules-details: -> the host's three determinism rules; (q) rules-details: + startup files change only between batches; (r) main's merge, seat run: foreground -> background, still detached (D45).

## User-visible changes

- Approved and kept: ## Approved user-visible changes.
- Asked as Q-H (r7): (s) after `plan-status.sh <plan> budget`, that plan's pane budget: fixed -> measured p90; (t) a merge starting mid-fetch: fast-forward -> skipped (D48).
- Asked as Q-I (r10), each kept by a guard test, before (the host's copy) -> after: (u) `--help` or `-h` on the 8 scripts in ## Guard fits: runs the script (token-ledger exits 2, the watchers start) -> prints its header and exits; (v) repeat-report, memory-flush, token-ledger and the readback stand-down with CLAUDE_CONFIG_DIR set: read ~/.claude, find nothing -> read that folder; (w) the fire-log summary: phase-queue-stop's refusals, no rule -> `phase-queue-open`.

## Question for the owner

- Q-H: (s) after a user runs the new `plan-status.sh <plan> budget`, the pane budget gate uses that plan's measured limits, not the fixed config; (t) the start-of-session sync also stands down, with its one line, when a merge starts during its fetch. O1 (rec.): both. O2: name one to drop.
- Q-I: so plugin tests pass: (u) 8 copied scripts print their header on `--help` instead of running; (v) copies reading Claude Code's folder honor CLAUDE_CONFIG_DIR; (w) phase-queue-stop's refusals log the rule `phase-queue-open`; and setup-gate.test.sh's pinned hook count goes 58 -> 65 for the 7 new hooks. O1 (rec.): all four. O2: name one to drop; its test then fails.

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- peer-code-sync: one 7 s fetch, two with a peer (host `timeout 7` lines, 2026-11-03).
- global-rules.md: 159 of 200 lines before C1 (`wc -l`, 2026-11-03).
- main startup print: 8,475 of 10,240 bytes per hook (`bash scripts/startup-size.sh`, 2026-11-03); card 221 bytes (`--help | grep usage:`).
- readback stand-down reads one settings.json: 1 entry in ~/.claude's (`grep -c compact-readback.sh`, 2026-11-03).

## Acceptance test

- test file path: hooks/__tests__/githooks-{commit-msg,pre-commit,pre-push}.test.sh (a home-path message is refused; Claude trailers are stripped; an empty message is left to git; a bare linked commit is refused; the override lets it through; headless -p git is refused; only the canonical Fast lane commits; an older linked worktree runs main's guard; a stray workspaces value keeps the default lane; a linked push is refused; headless -p is refused with the override)
- test file path: hooks/__tests__/bash-guardrails.test.sh (tail -f into grep gets a note; the default tier gets only the note; a lone gh run watch is rewritten; a linked suite run is not rewritten; quoted, empty and junk commands pass; a main suite run is rewritten; a foreground wait is backgrounded; merge and seat runs pass; a worker pane gets no wait note; a main with no Orca gets the note; a worker pane gets the hint)
- test file path: hooks/__tests__/{main-background-only,compact-readback,main-script-card,phase-queue-stop,peer-code-sync,brief-freshness-gate,bash-write-rules,test-skip-only-blocker,agent-startup-context,hook-tier,run-hook,hook-retire-when.guard,blocked-texts.guard,codex-parity.guard,setup-gate}.test.sh (a linked session is never rewritten; a bare inbox check is left alone; a measured-quick script passes; an unknown coordinator is not main; one rewrite per call; a clear sets no mark; a delivered checkpoint sets no mark; wired at compact|clear; the card is wired; a huge checkpoint prints cut; a user-level readback stands it down; a default-tier compact sets no mark; worker and reviewer panes get no card; the carried card checks; a failing --help adds no line; a slow --help holds nothing up; an open box refuses Stop; a later visitor is not held; the first Stop adopts the queue; a main ahead is never moved; no peer and dead origin exit 0; a live merge leaves main unmoved; a merge that starts mid-fetch leaves main unmoved; a dead cited path warns; no Environment line, no warning; a dead hooks/ path warns; a rule-glob write shows the rule once; another project gets its own rule; a model.fit( test passes; every stub names a heading; gated is strict; the hook guards pass, setup-gate at 65)
- test file path: scripts/__tests__/{new-test-count,help,project-main,hook-fire-log-summary,plugin,context-overhead,long-job,commit-hook-edits-untracked,plan-status-budget,wake-on-exit,merge-unit-local-baseline-raise,poll-agents,repeat-report,baseline-raise-check,token-ledger,memory-flush,ledger-codex-turn-usage.refute,ledger-missing-usage.refute,budget-context-metric.refute}.test.sh (no typescript: label regex; a moved test counts as new; .each counted once; a test_*.py file is counted; an empty diff prints 0; a second start fails; a refused message stays unread; a queued message is read once; an untracked file is never committed; an outside project runs the plugin's ledger; Claude totals are a unit row; the wake goes through to-main; a queued wake is stamped once; a launch needs no run file; a loosening unit needs the flag; concise check exits 2 loud; an unset log path reads the project's log; the script guards pass; a one-token budget refuses a linked pane)

## Claims to falsify

- new-test-count.sh's consumers see no change: line 1 the count, --edited, exit 0.
- builder-launch.sh:448 is the only linked commit lacking the override (Fast lane aside); a linked rebase fires no commit hook.
- Every copied file and fixture passes ci/leak-test.sh and the repo-wide guard tests; no new hook carries `"onFailure": "block"`.
- pp_sync_main refuses divergence; no-poll-loops.sh rewrites a bare inbox check; cos-own-echo.sh holds an empty banner.
- stop-checks.sh, run-shell-tests.sh --changed cover tier1-stop's generic part; break-run.sh red-proof's; seat.sh caps Builders.
- On Linux hs_cage with no size fails under `set -u`.
- No plugin file registers compact-readback in ~/.claude/settings.json.
- comment-audit as copied exits 1 on a clean tree.
- No plugin file writes `Split: recommended` or defines pp_orca_full before C2.
- After C4 a strict Write of a Python `model.fit(` test is allowed.
- No rewrite names long-job.sh or wake-on-exit.sh without ORCA_TERMINAL_HANDLE.
- peer-code-sync never moves main while a merge holds its lock or a live state; the merge's `flock -o` waits, never refuses.
- No copy reads Orca's current-run; a default-tier compact never blocks Stop or restarts main.
- A project with no hooks/file-size-cop.sh never meets the --baseline-raise refusal.
- repeat-report's default log is the file ruling-log.sh writes.
- Main's merge and seat runs detach, foreground or backgrounded.
- No plugin setting caps a main foreground Bash call at 30 s.
- Ledger tests in a scratch main checkout see `/fixture/ws`.
- No copy names board.sh

## Progress notes

Format: the Builder rewrites each line to `G<n>: built` or `G<n>: partial -- <what is left>`.
- G1: not started
- G2: not started (partial by design: pre-push review, contract and fast-set checks, protected files, mutation note, D2b)
- G3: not started (partial by design: repeat-report only, D2b)
- G4: not started
- G5: not started
- G6: not started (partial by design: host test runs and suites, paved-road registry, C1 Drops)
- G7: no change (D2 routing keys; D2b rule-drift.py and rule-drift.json)
- G8: not started (partial by design: tier1-stop, inbox waiters, banner peek, codex-long-poll, hook-deadline, D2 and D2b)
- G9: not started (partial by design: D2, D2b)
- G10: not started (partial by design: Adjacent, D14)

## Before the push

- Codex passes run until clean (builder-codex-pass.sh).
- Full shell tests on the PC: `bash scripts/run-shell-tests.sh`.
- `bash ci/leak-test.sh` clean.
- CHANGELOG.md release notes in the house style (C7).

## Routing

- Helpers: Sonnet general-purpose for reading code, test triage and mechanical copies (one per cut C2, C3, C5, C8); Haiku Explore for searches. Name the model on each call.
- This pane keeps cut order, the C2-to-C3 contract (long-job.sh, wake-on-exit.sh), the C3-to-C5 contract (main-background-only asks bash-guardrails) and final integration.

## Done

Done: none, the unit closes no issue.

## Issue cases

Issue cases: none, the unit closes no issue.

## Plan change log

- 2026-11-03 owner Q1: User-visible changes approved; refusals 0.68.0 made notes land as notes (D3).
- 2026-11-03 owner Q2: a moved test counts as new (D5).
- 2026-11-03 owner Q3: keep the 7 helper scripts (D15); unit-ready, unit-map and evidence-facts are out (D24).
- 2026-11-03 owner Q4 option 1 (A6, D21); Q5 all seven (D22); compact-readback O1 (D23).
- r2 (r1 findings): Fast lane kept (D13); plugin-held and host-only parts dropped (D2, D2b); tier asked; .delivered (D16); build order; skips name inputs; Drops; main gate (D10); A6; D3 classes; stubs (D7); D18-D20; refute tests carried; Data design fixed.
- r3 (both r2 judges NO-GO; no earlier pick): D25, Q-B; D23, A8; Q-A; notes main-only, hint (D26); pre-push override; D2, D2b reasons; D29; handoff reset; to-main exit 3; D13, D28, D20; D27, A7; Q-C; failure mode 3.
- 2026-11-03 owner: Q-A O1 (D37), Q-B O1 (D38), Q-C O1 (D39); removed from Question for the owner.
- r4 (both r3 judges NO-GO; no earlier pick on Q-D): Opus 1 handoff touch strict and under Orca (D31), (j); Opus 2 rewrites need Orca (D30); Opus 3 sync stands down mid-merge (D32), (l); Opus 4 skip guard exits on `*.py` (D33); Opus 5, Sol 1 wake via to-main (D34); Opus 7 validate_acceptance dropped, folders mapped (D11), (k); Opus 8 hint every pane (D26); Opus 9 hook-deadline reason (D2); Sol 3 absolute hooksPath (D35), (m); Sol 4 baseline-raise-check (D36), (n); sections cut to caps.
- r4 rebuttals: comment-audit (Opus 6, Sol 2): as copied its marker grep flags 4 lines in the guards that ban the markers and its name grep 1,271 lines, so it exits 1 on a clean tree; passing needs a new word list, a redesign (D2b). review-findings (Opus 10, Sol 2): it fills a per-round count the unit ledger keeps null by design (unit-ledger.sh:15-16); copying it changes that row contract (D2b).
- r5 (both r4 judges NO-GO; no earlier pick on Q-E; 74/6400 -> 75/6460): Opus 1, Sol 3 compact-readback on the STRICT list (A6); Opus 2 pp_orca_full (D41); Opus 3 exact rule text (D29); Opus 4 quick list (D43); Opus 5 paths mapped (C2); Opus 6 Split arm dropped (D11); Opus 7 step after BRANCH (D36); Opus 8 D33 restated, (o); Opus 9 lane rule (D13); claims reworded; Sol 1 CAP fixture; Sol 2 determinism, (p); Sol 4 hint after the gate (A6); Sol 5 ruling-log path (D42); Sol 6 skip gates (C4).
- 2026-11-03 owner: Q-D O1, Q-E O1 and Q-F (copy the evidence rule whole, with the re-read note) (D44, D40); Q-D and Q-E removed from Question for the owner.
- r6 (both r5 judges NO-GO; no earlier pick on Q-G; 75/6460 -> 76/6595; tests 473 -> 483): Opus 1 card tests carried (Carried tests); Opus 2, Sol 5 rule ranges cut per sentence and line (## Rule text); Opus 3 D10's non-0 returns, new case; Opus 4 every cut through builder-codex-pass.sh, hooksPath absolute (Cuts); Opus 5 30 s wording (D46); Opus 6 rule lines sourced; Opus 7 empty message and diff cases; Opus 8 n1-check input named; Sol 1 poll-agents fixture (C2); Sol 2 both_check owners, (r) (D45); Sol 3 bash-write-rules fixtures; Sol 4 (q).
- 2026-11-03 owner: Q-G O1, (q) and (r) (D47); Q-G removed from Question for the owner and Build order.
- r7 (both r6 judges NO-GO; no earlier pick on Q-H; 76/6595 -> 76/6640; tests 483 -> 484): Opus 1 comments.md headings `###` (Rules-details text); Opus 2 quick list: 9 names, no output (D43, Test edits); Opus 3 pane pin (Carried tests); Opus 4, Sol 1 bash-write-rules fixture named, ordered, sized, 3 checks remapped, floor 6; Opus 5 card stubs; Opus 6 ponytail tags (D49); Opus 7 (s), Q-H; Sol 2 sync's fast-forward under the merge lock (D48), new case, Break, What can go wrong row 3, (t), Q-H.
- r8 (r7: Opus GO, Sol NO-GO; no Q-I; no new user-visible item; 76/6640 -> 76/6646; tests 484, unchanged, no case added): Sol 1, Opus 3 heading map for every retained host check naming `# API and Data Conventions` or `# Security Review Policy`, each `has` check kept; marks trap to COMMANDECK_SCRATCH; :61's host scratch path mapped (leak word) (new ## Fixture maps); Opus 1 `(see the next section)` cut, :18 ends with a full stop (Rules-details text); Opus 2 card stubs in a scratch plugin tree (Carried tests); Opus 4 Data design main-ref row names D48's lock. Q-H left as found (main records O1).
- r9 (r8: Opus GO, Sol NO-GO; no Q-I, no new user-visible item; 76/6646 -> 76/6662; tests 484; Build order unchanged): Sol 1 ledger tests in a scratch checkout, 5 audited (A9, Carried tests); Sol 2 `long-jobs`; Sol 3 30 s clause (D46); Opus 1 rules folder mapped, own hook run, case spelled (Data design, C5, Fixture maps).
- r10 (r9: Opus GO, 3 LOW; Sol NO-GO, 3 P1; no earlier pick on Q-I; 76/6662 -> 77/6692; tests 484 -> 485; C6 also after Q-I): Sol 1-3 and a sweep of the repo-wide guard tests on the raw copies (new ## Guard fits; (u)-(w), Q-I); 19 validate_acceptance labels named (Test edits); Opus 1, 2 (new ## Refute fixtures); Opus 3 (Fixture maps); approved items moved to their own section; Q-H reworded to fit the cap, not re-asked.
- r11 (r10: Opus GO, 7 LOW; Sol NO-GO, P1, P2; no Q-J or user-visible item; 77/6692 -> 77/6700; tests 485 -> 454, drops named): Sol 1 (## Wake-on-exit fit), a sweep of the carried tests (the two test fits sections); Sol 2 (C2, C3); Opus 1 (D9); 2-4, 7 (Refute, Guard fits); 5 (C2); 6 (D2b); a ledger claim (A9).

## Facts

- Hooks wired relative; pre-push checks main, test wires absolute; Builders never commit; Codex pass: test-rules, line 1, override, builder-launch lacks it; Fast-lane path, real value only; pp_sync_main refuses divergence; bare check rewritten; empty banner held; Codex routes Bash, mcp, patch -- CONTRIBUTING.md:17, .githooks/pre-push:3-20, scripts/__tests__/ci-pre-push.test.sh:28, templates/_builder-brief-template.md:231-232, scripts/builder-codex-pass.sh:164, scripts/builder-codex-pass.sh:1632-1640, scripts/builder-codex-pass.sh:1818-1912, scripts/builder-launch.sh:447-449, scripts/fast-lane.sh:26, scripts/project-main.sh:105-123, scripts/paths.sh:1016-1029, scripts/merge-unit-local.sh:254, scripts/builder-launch.sh:240, hooks/no-poll-loops.sh:205-217, hooks/cos-own-echo.sh:40, hooks/codex-dispatch.sh:338-342 (observed: 2026-11-03)
- Strict off, list pinned; rewrites strict; pp_is_main_pane 0 main or no Orca, 1-3 not; handoff mark asked once; .delivered once, reset on restart; unready checkpoint holds Stop; Moved check 0; stubs "3 3"; no per-round ledger counts; to-main 0, 3 queued, 1 lost; 0.68.0 notes; hooks find the plugin; startup cap; no blocking hook; help line; 58 hooks; pp_rm_rf via codex-helpers -- hooks/lib/project.sh:56-59, hooks/__tests__/hook-tier.test.sh:14-21, hooks/bash-guardrails.sh:101, hooks/lib/project.sh:99-110, hooks/context-line.sh:34-54, hooks/context-clear-stop.sh:50-86, hooks/resume-context.sh:181-185, hooks/lib/context-clear-restart.sh:125, scripts/__tests__/new-test-count.test.sh:25, hooks/__tests__/agent-startup-context.test.sh:186-188, scripts/run-shell-tests.sh:178-184, scripts/unit-ledger.sh:15-16, scripts/to-main.sh:9-29, CHANGELOG.md:7, hooks/agent-startup-context.sh:17, scripts/startup-size.sh:4-5, hooks/__tests__/hook-on-failure.guard.test.sh:2-3, scripts/answer-worker.sh:46, hooks/__tests__/setup-gate.test.sh:35, scripts/codex-helpers.sh:58 (observed: 2026-11-03)
- seat caps Builders, reads reviewer-floor; merge, seat detach under CLAUDECODE; setup merges global-rules; 200-line cap; no-backward-compat; no edit re-read; ponytail ban; D2 homes; tripwires quote markers; no Python test names; skip guard's JS patterns, fit( arm -- scripts/seat.sh:416-418, scripts/seat.sh:266, scripts/paths.sh:450-452, scripts/merge-unit-local.sh:58-59, scripts/seat.sh:203, scripts/setup.sh:653-654, scripts/instruction-lint.py:53, templates/global-rules.md:5, templates/global-rules.md:57-67, hooks/edit-content-tripwires.sh:256-259, hooks/lib/project.sh:38-43, scripts/main-watch.sh:1-5, hooks/agent-startup-context.sh:122, hooks/stop-checks.sh:11-20, scripts/break-run.sh:2-6, scripts/plan-worktree-close.sh:2, hooks/lib/pane-budget.sh:8, hooks/lib/test-path.sh:7-12, hooks/test-skip-only-blocker.sh:29-71 (observed: 2026-11-03)
- PP_SCRATCH; wait-test-run.sh; merge pid; Linux hs_cage needs a size; CAP=400, 500; merge-unit-local: one flag loop, briefs under PP_MAIN, BRANCH late, blocking lock; ruling log per project; card usage, seat collect, reviewer env; budget: status p90; gate: 0 in main; runner passes orca-ide on; a test stubs it -- scripts/paths.sh:64-68, scripts/wait-test-run.sh:2-3, hooks/merge-lock-guard.sh:49-54, scripts/host-services.sh:234-239, hooks/file-size-cop.sh:61-62, scripts/merge-unit-local.sh:65-75, scripts/merge-unit-local.sh:138, scripts/merge-unit-local.sh:232, hooks/ruling-log.sh:16-17, hooks/lib/project.sh:7-19, scripts/peek.sh:13, scripts/merge-unit-local.sh:21, scripts/seat.sh:45-48, hooks/agent-startup-context.sh:85, hooks/lib/pane-budget.sh:38-45, hooks/pane-budget-gate.sh:112, scripts/run-shell-tests.sh:300-316, hooks/__tests__/context-clear-stop.test.sh:28-43 (observed: 2026-11-03)
- One matcherless SessionStart; wake log, relay event; RE291; main pane lookup; session id runs Serena check -- hooks/hooks.json:4-11, scripts/paths.sh:356-379, scripts/__tests__/plugin.test.sh:239, scripts/paths.sh:962-986, hooks/pane-budget-gate.sh:158 (observed: 2026-11-03)

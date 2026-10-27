# Plan: plugin-open-b-2026-10-27: the sixteen open plugin issues, one unit

Owner's words: Order: the owner, 2026-10-27 09:0x ET: "start the plugin unit NOW with ALL open Commandeck issues". ONE unit, no split, whatever the size caps say.

Scope is #403-#418 (`gh issue list -R pushprove-max/Commandeck --state open`, 2026-10-27: exactly these sixteen).
Every requirement below traces to one of their issue texts (comments included) or to the plan spec's section for
it. Nothing else is added except the pre-existing defects this plan found on its path, each named as one.

Closes: #403, #404, #406, #407, #408, #409, #410, #411, #412, #413, #415, #416, #417, #418
Refs: #405, #414

- Planned size: 52 files, 1550 changed lines

Tier: Standard. LOCAL merge only. Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no
test-timeout raise. Tests run on the PC. No red or mutation proofs except the break runs this plan's `Break:` lines
name: each is run red before pass 1 and recorded in the evidence file as `Mutation-verified: <test file> -- <check
label>: RED, <how>`. One unit, no split.

Helper subagents: hand work to helpers on the smallest model that can do it, and name the model on every call:
`general-purpose` on Sonnet for reading code, test triage and mechanical edits, `Explore` on Haiku for search. The
Builder brief carries this line.

Sources of every port, from the host's local main: the script-offload squash `d0c6b8cc` (host 3226-3236 and 3238;
host 3237 was dropped there) with its one-line test follow-up `86dacea4`, and the rule-stubs squash `4dbaab87`.
`git diff d0c6b8cc main -- <file>` is empty for every host file this plan ports (2026-10-27), so the final committed
host code is the squash's. Host hunks are cited as `host <file>:<line>` at host HEAD. #416, #417 and #418 have no
host fix and are built from their issue texts. A host file whose name carries the host's relay-seat nickname is
called "the host's relay tick script" here.

Timed checks (existing time-bound checks in the test files this unit edits; every new case added to these files
is light, and none is a heavy fixture):
- `hooks/__tests__/batch-independent-looks.test.sh`: `sleep 0.3` at :17 and :45, `sleep 0.2` at :46, the 400 ms
  deadline at :47-52. C4's case goes after :28, before the :41-54 block.
- `hooks/__tests__/pane-budget-gate.test.sh`: the fake `sleep 30` at :63-67, the sleep shim at :76-89, 3 s waits
  at :110 and :115. C5's and C6's cases go after :196, the last past-line case.
- `hooks/__tests__/ruling-log.test.sh`: the lock-holder poll at :88-90 and `sleep 1` at :92. C6's flip is the
  existing case at :45-46, in place.
- `hooks/__tests__/agent-startup-context.test.sh`: `sleep 20` under `timeout -s KILL 3` at :183-185. C6's and C7's
  cases go before it.
- `hooks/__tests__/context-clear-stop.test.sh`: `wait_for` with a 30 s deadline at :66. C5's cases go after the
  last existing case (:329-331), before the summary line at :334.
- `scripts/__tests__/seat-run.test.sh`: the `sleep 60` at :58 and the 100 x 0.2 s poll at :61. C4's prompt case is a
  grep of the recorded prompt and goes after :36, before them.
- `scripts/__tests__/bgrun.test.sh` (new) carries the host's own timed cases: a `sleep 2` job under `--max 1` then
  `wait --max 20` (about 3 s), and `wait --max 1` on a `sleep 30` child. They stay in the host's order, with the
  "unrelated sleep is never killed" case last.
- The heaviest new fixture is C6's lane creation in `scripts/__tests__/update.test.sh` (two stubbed `worktree
  create` calls and two real `git worktree add` runs). That file has no time-bound check (`rg -n 'timeout
  [0-9]|sleep [0-9]|deadline|%3N' scripts/__tests__/update.test.sh` is empty, 2026-10-27), and the case goes last.

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

- L1 (#405). The plugin's relay seat runs 5 watcher scripts (`ls scripts/cos-watch-*.sh scripts/cos-check.sh | wc
  -l` = 5, 2026-10-27). Every one writes its seen-state before its final print:
  - `cos-watch-decisions.sh:21-22`
  - `cos-watch-limit.sh:30-31`
  - `cos-watch-alerts.sh:70-77`
  - `cos-watch-inbox.sh:219-231`
  - `cos-check.sh:33-35`, after a `sleep 3000` at :14
  The final print is `cat "$f"` in `cos-lib.sh:22-23`. The host's rule (host plan check B2) leaves such a watcher out
  of a combined tick, which here leaves an empty set (Decision 3).
- L2 (#403). Main's startup card does not fit the startup print today. In a clean project (`git init`, a
  `commandeck.json` of `{version:1, profile:"claude"}`, `HOME` empty, the hook run from the main checkout,
  2026-10-27):
  - The hook printed 7,786 bytes, and its line 103 read `[left out to fit the 10,240-byte startup print: Read
    .../templates/main-session.md (5748 bytes) before anything else]`.
  - The always-on line read `2 repo/user files, 11366 bytes`.
  A card that fits needs about 3.5 KB more cut than #403's moves give (Decision 21). So after this unit, the card
  may still be left out. The pointer then names the card's line range, not the whole 21,513-byte file.
- L3 (#404/#411/#413). peek caps each item at 400 lines and the whole call at 60 KB, as on the host. The largest plan
  here is 2,203 lines (`wc -l .claude/plans/*.md | sort -n | tail -2`, 2026-10-27), so it pages in 6 calls.
- L4 (#407/#417/#406). A worker's waits share one budget: `LIMIT` = 270 s, or 540 s on the 1-hour cache
  (`hooks/no-poll-loops.sh:233-239`). No `BASH_MAX_TIMEOUT_MS` is set anywhere in `config/`, `templates/` or
  `scripts/` (`rg -n BASH_MAX_TIMEOUT_MS`, 2026-10-27). The largest rewritten timeout field, 540000, is under Claude
  Code's default 600000 maximum.
- L5 (#418). A rewritten worker search runs to its end, so that its exit is its own. Only 200 lines reach the
  context. A flood bigger than the pipe buffer costs the search's full run time. Measured with rg 15.2.0, in bash
  and zsh: flood 0, no match 1, bad pattern 2 (2026-10-27).
- L6 (#416). Lanes are found by folder name, as the relay is (`${TOP##*/}`, `hooks/pane-budget-gate.sh:63`). A
  project whose own unit is named `Fast-lane` or `Research-lane` collides, as one named `Chief-of-Staff` does today.

## Main answers

- New queue items are numbered past the highest Q-number in both the current and the inherited checkpoint, as the host does; test the inherited `Q-1` collision.
- An automatic skeleton snapshot is not restart-ready: the Stop path refuses a checkpoint whose Goal or unit cells are unfilled, with or without a resumed-from record; regression test the `s1` sequence, separate from the fill test.
- A plan judge's bundle reads the frozen plan copy its seat spec names, never the live plan; test different sentinels in the live and frozen plans.
- The Fast-lane landing records the reviewed commit (its verdict comes from the reviewer's record, next line but one), lands that exact commit, refuses a differing tip, and needs a new review after any change; it has a `Catches:` line; test the A-then-B sequence.
- The Fast-lane landing never takes a verdict the lane typed: `land` reads it for the recorded sha from the reviewer's own session record, as the normal merge script does, and refuses when that record is missing, names another sha or is not `VERDICT: GO`; test a hand-typed GO with no reviewer record.
- Owner, 2026-10-27: saved drop/keep-mine ids are not kept across the stub move (no MADE_FROM pair, no migration test); the release notes tell users to save those choices again.
- Owner, 2026-10-27: #405 and #414 stay open with `Refs`; fourteen issues close.
- The loop-budget refusal case uses an outside sleep of 231 s, and 230 s stays eligible.
- The checkpoint fill test asserts only that the promised Goal and table placeholders are gone.
- Decision 2's test is the existing `hooks/__tests__/builder-search-guard.test.sh`.

## Question for the owner

None blocks this plan. Two issues stay open with `Refs`, and each needs the owner's call to go further:
- #405's combined watcher tick: build it by making each relay watcher print before it marks its news seen (a
  change to five watchers' state order, not a port), or leave the watchers armed in parallel as they are?
- #414: drop main's on-screen checklist (the owner's own rule, `templates/main-session.md` Details, "Checklist"), or
  keep it hand-kept? The host dropped its twin because a script-written task never reaches the on-screen list.

## 1. Item map (what exists, what the host built, where it lands, the cut)

| Issue | Host hunks ported | Plugin today (file:line) | Lands at | Cut |
|---|---|---|---|---|
| #418 | none (host 3240 is open) | the search refusal `hooks/bash-guardrails.sh:289-345` (`root_like` :301, `search_bounded` :322, block text :579); no rewrite yet | the C1 rewrite text | C1 |
| #407 search | host `bash-guardrails.sh:23-30` (`rewrite_safe`), `:747-765` (every operand counted), `:769-787` (worker rewrite, `updatedInput`, no `permissionDecision`); host `bash-guardrails-search.refute.test.sh` | refuses every role; `seg_words`, `load_words`, `load_segments` diff 0 lines against the host's pre-unit file | after `hooks/bash-guardrails.sh:102`; the search block :289-345 and :579 | C1 |
| #407 loop, #417 | host `no-poll-loops.sh:484-496` (`timeout $L bash -c` rewrite, `L = LIMIT-10-WAITED`, timeout field `(L+10)*1000`, L >= 30). Not ported: host `:93-193` and `:209-317`, the host's own tokenizer and wait parser. The plugin has its own (`NPL_WORDS`, `hooks/no-poll-loops.sh:103-184`), which already refuses what it cannot read (:370-373) | the worker sleep loop is refused at `hooks/no-poll-loops.sh:366-369`; `walk()` :338-354 lumps every looped wait into one `loop` flag; `secs()` :306-311 | `hooks/no-poll-loops.sh:338-369` | C2 |
| #408 | host `main-background-only.sh:59-77` (run in background instead of block). No plugin twin: no plugin hook blocks a slow foreground command (`rg -n 'run_in_background' hooks/` hits only `no-poll-loops.sh:232,367,371,471`). The one background block the plugin has is the foreground Orca wait at `no-poll-loops.sh:470-475` | refuses a foreground `orchestration check --wait`; `scripts/orca-wait.sh:591-593` already prints the state block on every wake and "nothing was queued." on a repeat | `hooks/no-poll-loops.sh:470-475` | C2 |
| #406 | host `bgrun.sh:1-71`, `bgrun.test.sh`; host `no-poll-loops.sh:68`, `:233-267`, `:303-307` (bgrun waits count). Not ported: host `long-job.sh` `run)` (:126-146), since the plugin has no `long-job.sh` (`rg 'long-job\|long_job'` = 0 hits) | none | new `scripts/bgrun.sh`; prefilter `hooks/no-poll-loops.sh:75`; `plain_wait` :326-338 | C3 |
| #404, #411, #413 | host `peek.sh:1-116`, `peek.test.sh`; host `batch-independent-looks.sh:184`; host `_implementer-tools.md:19-24`; host `_reviewer-tools.md:34-35`; `86dacea4` (startup test lists peek: no plugin twin, since the plugin test has no script list) | none; `plan_section` `scripts/builder-codex-pass.sh:1094-1098` stays | new `scripts/peek.sh`; `hooks/batch-independent-looks.sh:176`; `templates/_builder-brief-template.md:50`; the plan-judge spec text in `scripts/seat.sh` (~:425-450) | C4 |
| #409 | host `state-snapshot.sh:18-32`, `:43`, `:52-57`, `:116-172` (flags, temp then rename, fill, carry); host `context-line.sh:37-46` (snapshot once at the first crossing); host `pane-budget-gate.sh:23-25`, `:36-37` (the flagged form allowed past the line) | `scripts/state-snapshot.sh` (151 lines, flags :18-24, `open(out,"w")` at :84 with no rename, TODO cells :78, Goal placeholder `TODO one line:` :93); `hooks/context-line.sh:47-48` (marker), :55, :58; `hooks/pane-budget-gate.sh:25-39` (`one()` bans every quote) | as named | C5 |
| #416 | none (the host's lanes were made by hand) | relay worktree block `scripts/setup.sh:700-736`; relay settings `scripts/worktree-setup.sh:88-108`; worker settings :160-176; folder-name checks named in C6 | C6 | C6 |
| #403 | host `4dbaab87`: task-only text moved verbatim behind stubs `- **<topic>:** Details, <Topic>.`; duplicates given one home; the counter adds the printed worktree-rules bytes; a test that every stub names a section that exists | always-on: `templates/AGENT_STARTUP.md` (5,845 B), main's card (`templates/main-session.md` above Details, 5,521 B), `templates/global-rules.md` (8,331 B) and `templates/global-claude.md` (4,651 B) in `~/.claude/CLAUDE.md`; counter `hooks/agent-startup-context.sh:194-212` | C7 | C7 |
| #410 | host brief template :55 (one line) | `templates/_builder-brief-template.md:84` | after :84 | C7 |
| #412 | host `AGENT_STARTUP.md:15-16` (the startup ToolSearch line gains `Monitor,SendMessage`) | no startup ToolSearch line (`rg -n 'ToolSearch\|select:' templates/` hits only `checkpoint.md:82`) | `templates/AGENT_STARTUP.md` "Rules for every pane" (:70-89) | C7 |
| #415 | host `CLAUDE.md` "Ban:" sub-bullet (the host deferred it to its protected file) | the plugin's always-loaded style text is `templates/global-rules.md:9-10` ("Talk to the owner in plain English") | a new bullet after `templates/global-rules.md:10` | C7 |
| #405 | host relay tick script (not ported, Decision 3); host built no relay-answer script either, because its relay-order script already answered in one call (host Decision 9) | `scripts/relay-order.sh:60-78` finds the ruling id, records with `decision.sh answer`, marks seen and sends with `to-main.sh question`, in one call; the ruling log is written by `hooks/ruling-log.sh` | nothing | -- |
| #414 | none (host 3237 dropped: a script-written task never showed in the list) | the owner's checklist rule `templates/main-session.md` Details "Checklist"; `hooks/checklist-guard.sh` | nothing | -- |

## 2. Cuts (build order)

Each cut lists what it changes, what it Produces and Consumes, the existing consumers of any contract it changes, its
size (changed lines: code, tests and docs), its acceptance tests and its `Break:` lines.

Shared-file edit order: `hooks/no-poll-loops.sh` and its test C2, C3; `hooks/pane-budget-gate.sh` and its test C5,
C6; `hooks/agent-startup-context.sh` and its test C6, C7; `templates/_builder-brief-template.md` C3, C4, C7;
`docs/hooks.md` C1, C2, C4, C5, C6; `README.md` C6, C8;
`CHANGELOG.md` and `.claude-plugin/plugin.json` C8 last.

Builder check B1 runs before C1. B1 decides whether C1 and C2 rewrite or stay as they are.

### C1 -- #407 search half and #418: a worker's unbounded search is rewritten, capped, and keeps its own exit (~95 lines, 3 files)

1. `hooks/bash-guardrails.sh` after :102: the host's `rewrite_safe` (host :23-30). It is run on the raw command
   before anything is stripped, and it refuses a rewrite when the raw text holds `$`, a backtick, a backslash, a
   newline or a process substitution, quoted or not. The rest is read through the plugin's `strip_quoted`, which is
   already loaded fail-closed at :99-100. The search caller adds its own shape: no `| ; & < > ( )`, and no unquoted
   `~ * ? [ {`.
2. The search block (:289-345): every operand is counted, with no `break` (host :747-765).
3. The rewrite (host :769-787), in a linked worktree that is not main (git dir differs from the common dir) only. A
   missing path, `.`, the checkout root or a literal parent of it becomes the checkout root. The output is
   `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecisionReason":"<what was rewritten and why>",
   "updatedInput":(.tool_input + {command: <new>})}}`, exit 0, with no `permissionDecision`.
4. The rewritten text is the #418 fix: `( set -o pipefail; { <words>; } 2>&1 | { head -n 200; cat >/dev/null; } )`.
   - The subshell keeps `pipefail` from leaking.
   - The drain lets the search finish, so the exit is the search's own: 0, 1 or 2, never `head`'s and never 141.
   - It runs the same in bash and zsh, the shell the Bash tool runs here, where `PIPESTATUS` does not exist (L5).
5. Still refused as today:
   - main;
   - two unbounded operands (`rg foo . /`);
   - a `$var` or `$()` operand;
   - any pipe or chain (`rg x . | head`);
   - every call `rewrite_safe` refuses.
   `hooks/builder-search-guard.sh` is unchanged (Decision 2).
6. `docs/hooks.md:50` (the bash-guardrails row): one clause says that in a worker pane an unbounded search is
   rewritten to the checkout root and capped at 200 lines.

Produces: the rewrite JSON above, for one simple worker search. Consumes: B1, `strip_quoted`, the existing `shq`
(:226). Consumers of a changed contract: the Bash tool (it runs `updatedInput`); `hooks/no-poll-loops.sh` runs
after this hook on the same call, and its rewrites never match a lone search (Claim 3).

Tests (`hooks/__tests__/bash-guardrails.test.sh`, a `git worktree add` fixture added in the host's `in_dir` style,
cases after :102):
- "worker root rewrite capped; main still blocked; $f still blocked"
- "a rewrite never changes what the search covers or matches" (`rg -n foo . /`, `rg -n "$needle" .`, `rg foo* .`:
  exit 2)
- "a rewrite runs exactly what the call would" (`rg -n "$(touch x)" .`, a backtick, `rg "a'b" * "c'd"`: exit 2 and
  no updatedInput; the same worker cases from a plain non-worktree checkout: exit 2)
- "a rewritten search returns rg's own exit" (#418): run the rewritten command against a 3-file fixture in bash, and
  in zsh when it is installed. `rg -q 'a^' .` gives 1, `rg '[' .` gives 2, a 300-line match gives 0 with exactly 200
  lines printed.

Break: hooks/__tests__/bash-guardrails.test.sh -- "main still blocked" -- hooks/bash-guardrails.sh:<C1 rewrite> remove the linked-worktree test
Break: hooks/__tests__/bash-guardrails.test.sh -- "$f still blocked" -- hooks/bash-guardrails.sh:<C1 rewrite> skip the `rewrite_safe` call
Break: hooks/__tests__/bash-guardrails.test.sh -- "a rewritten search returns rg's own exit" -- hooks/bash-guardrails.sh:<C1 rewrite> drop `set -o pipefail` from the rewritten text

### C2 -- #407 loop half, #417, #408: a worker sleep loop and a foreground inbox wait are rewritten (~145 lines, 3 files)

1. `walk()` (`hooks/no-poll-loops.sh:338-354`) splits its one `loop` flag in two:
   - a looped `sleep`, whose operand goes through `secs()` (:306-311);
   - every other looped wait (an ask's `--timeout-ms`, `wait-test-run.sh`, and from C3 `bgrun.sh`), which stays
     refused as today.
   `total` counts only the waits outside a loop.
2. #417. A looped sleep is rewritten only when every looped sleep operand reads as a finite number. `sleep inf`,
   `sleep infinity`, `sleep $T` and any operand `secs()` cannot read stay refused, as now. Today's plugin refuses
   `while true; do sleep inf; done` (it does not reproduce here). The case pins that a port of the host's
   digit-first detector (host `no-poll-loops.sh:480`) never lands. A suffix form (`sleep 1h`, `sleep 5m`) is finite
   and is rewritten, bounded by the `timeout`.
3. #407. A worker call (git dir differs from the common dir, :33-34) whose only refusal is a looped sleep is
   rewritten, as on the host (host :484-496):
   - The command becomes `timeout <L> bash -c <shq of the whole call>`, and the Bash `timeout` field becomes
     `(L+10)*1000`.
   - L = `LIMIT` - 10 - the call's waits outside the loop. With the loop as the call's only wait, L is 260, or 530
     on the 1-hour cache.
   - L under 30 keeps today's refusal.
   - Exit 124 means "wait again". `permissionDecisionReason` says so.
   - Main's sleep loop stays refused (:488).
4. #408. A foreground `orca-ide orchestration check ... --wait` (:470-475) is no longer refused, in any pane. It is
   rewritten to `.tool_input + {run_in_background: true}`, with the reason "a foreground Orca wait blocks typing;
   it now runs in the background".
5. The header comment (:14-27) and the refusal text at :367 name the rewrite. `docs/hooks.md:20` (the no-poll-loops
   row) gets one clause for each rewrite.

Produces: two rewrite shapes, each with `updatedInput` and no `permissionDecision`. Consumes: B1, `LIMIT`
(:233-239), `secs()`, `shq` (copied from `bash-guardrails.sh:226`, the hook has no shared lib for it). Consumers of
a changed contract: the Bash tool; `templates/main-session.md:11` still reads true (main stays refused).

Tests (`hooks/__tests__/no-poll-loops.test.sh`, worker cases through `run_wt`/`rc_wt` at :214-228):
- Flips from refused to rewritten: the existing cases at :229-232, :258-260, :264 and :357-358, and :280 (`sleep
  +1`) if `secs()` reads it. The evidence names each flip.
- Stay refused: :262-263.
- New cases:
  - "worker loop rewritten; main loop blocked"
  - "quoted loop rewritten intact": `while ! grep -q 'done x' f; do sleep 5; done`; the inner text is byte-identical
    after `bash -c` unquoting.
  - "worker loop shares the call's wait budget" (TTL unset, so `LIMIT` = 270): `sleep 231;` before the loop gives
    exit 2 (L = 29); `sleep 100;` before it is rewritten with `timeout 160` and Bash timeout 170000.
  - "a loop left exactly 30 s is still rewritten": `sleep 230;` before the loop is rewritten with `timeout 30` and
    Bash timeout 40000 (L = 270 - 10 - 230 = 30, the bound).
  - "a non-numeric sleep in a worker loop is refused" (#417): `while true; do sleep inf; done`, `... sleep
    infinity ...` and `... sleep $T ...`, each at timeout 600000, give exit 2.
  - "a suffix sleep in a worker loop is rewritten under the budget": `sleep 1h`.
  - "a foreground inbox wait is rewritten to the background" (#408): updatedInput keeps `command` and adds
    `run_in_background: true`, with no `permissionDecision`. A call already in the background exits 0 with no output.

Break: hooks/__tests__/no-poll-loops.test.sh -- "worker loop rewritten; main loop blocked" -- hooks/no-poll-loops.sh:<C2 item 3> remove the worker test
Break: hooks/__tests__/no-poll-loops.test.sh -- "worker loop shares the call's wait budget" -- hooks/no-poll-loops.sh:<C2 item 3> set L to LIMIT-10 without subtracting the call's other waits
Break: hooks/__tests__/no-poll-loops.test.sh -- "a non-numeric sleep in a worker loop is refused" -- hooks/no-poll-loops.sh:<C2 item 2> accept any looped sleep operand

### C3 -- #406: a background job returns its exit and tail in one call (~110 lines, 4 files)

1. New `scripts/bgrun.sh`, the host's `bgrun.sh:1-71` with these changes:
   - `--help`/`-h` is answered before anything is sourced (`scripts/__tests__/help.test.sh:13-25`).
   - The log goes to `$PP_SCRATCH/bgrun/<epoch>-<pid>.log` (`scripts/paths.sh:64`).
   - The wait limit is wait-test-run's own rule: 270 s, or 540 s on the 1-hour cache (`scripts/wait-test-run.sh:18`).
     The host's 240 does not match this plugin.
   - The printed wait line names this script's own path.
   Interface:
   - `bgrun.sh [--max S=25] [--lines N=20] -- <cmd...>`: done within S prints `rc=<n>` and the last N lines, exit =
     the command's. Otherwise it prints "still running pid=<p> log=<f>; wait with: bash <path>/bgrun.sh wait <f>",
     exit 3.
   - `bgrun.sh wait <log> [--max S] [--lines N]`: `rc=<n>` and the tail, exit = the command's. Still running: exit
     3. No child and no `.rc`: "died with no exit code", exit 1.
2. `hooks/no-poll-loops.sh`:
   - The prefilter (:75) gains `bgrun`.
   - `plain_wait` (:326-338) counts a `bgrun.sh` segment: its last `--max` before any `--`, or else 25 for a run and
     `LIMIT` for `wait`.
   - A looped `bgrun.sh` is refused like a looped `wait-test-run.sh` (C2 item 1).
3. `templates/_builder-brief-template.md` (background tests, :113-120): one sentence. "Any other background job: `bash
   {scripts}/bgrun.sh -- <cmd>` returns its exit and tail in the same call when it ends within 25 s; otherwise wait
   with the line it prints."
   `brief-template.test.sh` pins sentences there, so this sentence is added and none is reworded.

Produces: the interface above; `<log>` and `<log>.rc` (Data design). Consumes: `PP_SCRATCH`, wait-test-run's limit
rule (copied). Consumers of a changed contract: no-poll-loops' wait count (item 2).

Tests (new `scripts/__tests__/bgrun.test.sh`, the host's 8 checks with the plugin's paths and limit;
`no-poll-loops.test.sh`):
- "quick job prints rc and tail inline"
- "any command: exit 7 and its output come back through the printed wait line"
- "a child killed before it wrote an exit code: exit 1, died" (an unrelated `sleep 300` started by the test outlives
  it)
- "bgrun waits count against the worker wait budget": two `bgrun.sh wait` in one worker call give exit 2, "can wait
  up to 540 s in all". One gives exit 0. `bgrun.sh --max 25 -- true; bgrun.sh wait /tmp/a.log` gives exit 2.
- "a bgrun wait inside a worker loop is refused"

Break: scripts/__tests__/bgrun.test.sh -- "any command: exit 7 and its output come back through the printed wait line" -- scripts/bgrun.sh:<wait> exit 0 instead of the `.rc` value
Break: hooks/__tests__/no-poll-loops.test.sh -- "bgrun waits count against the worker wait budget" -- hooks/no-poll-loops.sh:<plain_wait> remove the `bgrun.sh` term

### C4 -- #404, #411, #413: one call prints several files, slices, sections or a reviewer's bundle (~215 lines, 8 files)

1. New `scripts/peek.sh`, the host's `peek.sh:1-116`:
   - Items are `path`, `path:A-B`, `path#Heading`, `-g <pattern> <path>` (`rg -n -C2`), `--unit <unit>` and
     `--unit <unit> --closing`.
   - Each item gets an `== <item> ==` header. Each item is capped at 400 lines with "cut at 400; resume: peek.sh
     <path>:401-<n>", and the whole call at 60 KB.
   - It exits 2 on the checkout root or its parent, and 1 if any item is missing.
   Adaptations:
   - The script path is `scripts/peek.sh`, and the test root climbs `../..`.
   - The paved-road file is `.claude/paved-road.md`, not the host's `policy/` path (`scripts/plan-check.sh:42`).
   - The host's `<unit>-map.md` and `_reviewer-tools.md#Read cold` items are dropped: the plugin has neither file.
   - The closing bundle's heading list reads `## Decisions`, not the host's "Decisions already made". The plugin's
     heading is `## Decisions` (`scripts/seat.sh:432`), and `section()` matches by prefix.
   - Every other heading keeps its host name: Accepted failure modes, Stated limits, Claims to falsify, Plan change
     log (`seat.sh:436`, :445).
   - The diff stat is `git diff --stat main...HEAD`, the branch name the pass script uses
     (`scripts/builder-codex-pass.sh:168`).
   - The bundle reads only named paths, so no evidence, round report or change log can enter.
   - `--unit <unit> --plan <file>` reads the plan from `<file>` in place of `.claude/plans/<unit>.md`; every other
     bundle item is unchanged. A missing `<file>` is a missing item: exit 1, and the live plan is never read in its
     place. This is how a plan judge reads the frozen copy its seat spec names (item 4).
2. `hooks/batch-independent-looks.sh`, after :176 inside the ADVICE heredoc: one line naming `peek.sh` by its full
   path. The heredoc is unquoted, so the path comes from a variable the hook sets from `${BASH_SOURCE[0]%/*}/../scripts`.
   `docs/hooks.md:53` (batch row) names it.
3. `templates/_builder-brief-template.md` after :50: one sentence. "Several looks in one call: `bash
   {scripts}/peek.sh <file>:<a-b> '<file>#<Heading>' -g <pattern> <file>`." The pinned sentence at
   `brief-template.test.sh:16` is unchanged.
4. The plan-judge prompt `scripts/seat.sh` builds (the `plan-judge-*` `SPEC_TEXT` lines, :439-441): one line, added
   only when the launch froze the plan (`$SNAP` set at :403-408). It names the frozen copy by its real path: "Print
   your inputs in one call with `bash $PP_SCRIPTS/peek.sh --unit $UNIT --plan $SNAP`: it reads the read-only copy
   your spec's Plan: line names, never the live plan." With no frozen copy, no peek line is added, so a judge is never
   pointed at the live plan. This is the plugin's home for the host's `_reviewer-tools.md` line.
   `templates/global-rules.md` is not used, because it is always on (#403). A closing pass reviews the Builder's
   branch, whose plan is the branch's own, so `--unit <unit> --closing` stays as on the host.
5. `docs/commands.md` near :42-62: a 3-line `peek.sh` entry.

Produces: the interface above; the judge prompt's peek line. Consumes: seat.sh's frozen copy `$SNAP` and its spec
`Plan:` line (:403-408). Consumers of a changed contract: the plan-judge prompt, read by `scripts/__tests__/seat-run.test.sh:33-36`
(it reads the spec path from the prompt's first sentence, which is unchanged). `plan_section` in
`builder-codex-pass.sh:1094-1098` is not folded onto it, as the host left its own.

Tests (new `scripts/__tests__/peek.test.sh`, the host's 12 checks with the adaptations above; the host's case-filter
lib lines are dropped, since `hooks/__tests__/lib` does not exist):
- "three items, one call"
- "odd paths, missing heading, cap"
- "every cut says so"
- "refuses checkout root and its parent"
- "unit bundle: diff stat first, plan after, no evidence, rounds or change log"
- "closing bundle: diff stat and the plan's claim sections only"
- "an absent bundle file prints (none)", re-pointed at `.claude/paved-road.md`
- "a judge's bundle reads the frozen plan, never the live one": the live `.claude/plans/U.md` holds `LIVE-SENTINEL`
  and a read-only copy holds `FROZEN-SENTINEL`; `peek.sh --unit U --plan <copy>` prints `FROZEN-SENTINEL` and no
  `LIVE-SENTINEL`; `--plan <missing file>` exits 1 and prints no `LIVE-SENTINEL`.
- `scripts/__tests__/seat-run.test.sh`, after :36 (Timed checks): "a plan judge's prompt points peek at its frozen
  copy": the prompt holds `peek.sh --unit pu --plan $SNAP`, the same `$SNAP` the spec's Plan: line names.
- `hooks/__tests__/batch-independent-looks.test.sh`: "the batching advice names peek.sh", after :28 (Timed checks).

Break: scripts/__tests__/peek.test.sh -- "refuses checkout root and its parent" -- scripts/peek.sh:<path check> remove the root/parent check
Break: scripts/__tests__/peek.test.sh -- "closing bundle: diff stat and the plan's claim sections only" -- scripts/peek.sh:<unit> print the whole bundle when `--closing` is set
Break: scripts/__tests__/peek.test.sh -- "unit bundle: diff stat first, plan after, no evidence, rounds or change log" -- scripts/peek.sh:<unit> keep the `## Plan change log` section
Break: scripts/__tests__/peek.test.sh -- "a judge's bundle reads the frozen plan, never the live one" -- scripts/peek.sh:<unit> ignore `--plan` and read `.claude/plans/<unit>.md`
Break: scripts/__tests__/seat-run.test.sh -- "a plan judge's prompt points peek at its frozen copy" -- scripts/seat.sh:<judge peek line> name `--unit $UNIT` without `--plan $SNAP`

### C5 -- #409: one call writes main's checkpoint with its judgment fields (~335 lines, 10 files)

1. `scripts/state-snapshot.sh` takes `--goal <text>`, `--stage <unit>=<text>`, `--next <unit>=<text>` and
   `--open-item <text>`. Stage, next and open-item may each be given more than once. They are parsed beside today's
   flags (:18-24).
   - With no new flag, the output is byte-identical to today's.
   - With any new flag:
     - The checkpoint is generated as today if absent (the host kept this).
     - The plugin's Goal placeholder (`TODO one line:`, :93) is replaced, and the named units' TODO cells (:78) are
       filled.
     - `- Q-<n>: <text>` is appended at the end of `## Queue`, numbered past the highest `Q-<n>` in BOTH the current
       checkpoint and the inherited one, as the host does (host `state-snapshot.sh:119-121`, :156, :160). The
       inherited one is the first line of `~/.claude/checkpoints/<sid>.resumed-from` (written by
       `hooks/resume-context.sh:55-59`), and its whole text is scanned. With no record, only the current file counts.
       So a new item never takes an inherited item's number, which `checkpoint-context.py` `key()` (:194-201, `QKEY`
       :141) would read as that item carried (`kept`, :519, :523).
     - The save is a temp file then a rename in the same folder. Today's `open(out,"w")` at :84 is replaced for both
       paths.
     - Then the script runs `checkpoint-context.py carry <base> <cp>`, as `hooks/context-clear-stop.sh` does, and
       prints its result.
   - Refusals:
     - An unknown unit: exit 2 naming it, file unchanged.
     - A result that would still hold a TODO cell or the Goal placeholder: exit 2 naming each missing field (`Goal`,
       `<U> stage`, `<U> next`), file unchanged, so the retry is the same call with the named flags.
     - A failed rename: exit 1 "could not save the checkpoint", with the path not printed as saved.
2. `hooks/context-line.sh`: at the first crossing only (before the marker write at :47-48, with no checkpoint file
   yet), it runs `state-snapshot.sh --out <cp>` once, if B2 allows. The two messages (:55, :58) name the flagged call
   as main's one step past the line, in place of "write from the template".
3. `hooks/pane-budget-gate.sh`, `one()` (:25-39): past the clear line it also admits `[bash] <the plugin's
   state-snapshot.sh> --out <this checkpoint> [--force]` followed only by the four new flags. Each value is a single
   word or one single-quoted string holding no `'`.
   - The check strips the single-quoted values first and then applies today's character ban to what is left. So no
     chain, substitution, redirect or second line can ride a value.
   - An `--out` or `--force` inside a value is text, not a flag. Every other refusal is unchanged.
   - The block text (:47) names the flags.
4. `templates/main-session.md:37-38` (the clear-line instruction) names the one flagged call in place of the hand
   Write. The rule's id changes and no MADE_FROM pair is added (the owner's answer): a saved keep-mine or drop of
   the old id needs saving again, as the release notes say.
   `docs/checkpoints.md:7` and `docs/hooks.md:28`, `:51` each get one sentence.
5. `hooks/context-clear-stop.sh` gets a readiness check, so an automatic (unflagged) skeleton is never
   restart-ready. It has none today (`rg 'SKELETON|\| TODO|<one line' hooks` hits only the generator and the
   template).
   - Where: after the already-restarted check (:45-50) and before the carry block (:59). It runs whenever the
     checkpoint is fresh, with or without a `<sid>.resumed-from` record.
   - What it reads: the generator's two placeholders, the line `TODO one line:` under `## Goal` (`state-snapshot.sh:93`)
     and a `| TODO |` cell in a unit row (:78). Item 1's refusal reads the same two patterns. The other sections'
     TODO prompts (:105-137) and the explanatory sentence (:86) are not read: they are main's notes, not restart
     fields. A hand-written checkpoint from `templates/checkpoint.md` holds neither pattern (`rg -n TODO
     templates/checkpoint.md` hits only the TODO LIST line :81, 2026-10-27), so it is unaffected.
   - Outcome: the first stop blocks once (`decision:"block"`, the :69-78 style, reason under 400 bytes as the :168
     case pins), naming the unfilled fields and the flagged call. A stop with `stop_hook_active` true logs to
     `clear-hook.log`, prints "context-clear: <cp> still has unfilled fields; main is not restarted" and exits 0 with
     no restart (the :104-106 style).
   - `docs/checkpoints.md:7` gets one more sentence: an unfilled checkpoint does not restart main.
   - No existing case changes: no fixture in `hooks/__tests__/context-clear-stop.test.sh` holds `TODO` (`rg -n TODO`
     on it is empty, 2026-10-27).

Produces: the flags; the temp-then-rename save; the Stop readiness check. Consumes: B2; `checkpoint-context.py carry`
(same contract as the host); the `<sid>.resumed-from` record; `board.sh` (as today, :35). Consumers of the changed
checkpoint contract: `hooks/resume-context.sh:14,63,102,116-119,155`, `hooks/context-clear-stop.sh:33-100` (changed
by item 5), `hooks/lib/context-clear-restart.sh:62`, `hooks/pane-budget-gate.sh:12-48`, `templates/checkpoint.md`.
The file's shape is unchanged, only its cells are filled, so none of the others changes.

Tests:
- New `scripts/__tests__/state-snapshot.test.sh`, with a stub `orca-ide`/board in `$TMP/bin`, HOME a temp dir and U
  the only live unit:
  - "no flags: output unchanged"
  - "flags fill TODO cells, add Q items, run carry"
  - "unknown unit refused, file unchanged"
  - "one call fills the Goal and the named unit's cells": without `--goal`, exit 2 naming Goal with the file
    unchanged; with `--goal 'ship U' --stage 'U=build it' --next 'U=merge it'`, exit 0, `grep -c '^TODO one line:'`
    = 0 and `grep -c '^| U |.*| TODO |'` = 0. Nothing else is asserted about `TODO`: the other sections keep their
    prompts.
  - "a new queue item never reuses an inherited number": the inherited checkpoint (named by `<sid>.resumed-from`)
    holds `- Q-1: obtain approval` under its open items, the current one has no Q item, and the call adds `--open-item
    'investigate unrelated failure'`. The new item is `Q-2`, no `Q-1` line is in the new file, and the carry result
    the script prints still lists `Q-1: obtain approval` as not carried.
  - "a failed save is never reported as saved"
- `hooks/__tests__/context-clear-stop.test.sh`:
  - "first crossing writes the snapshot once".
  - "an unfilled automatic snapshot never restarts main" (the judge's sequence): session `s1` has no checkpoint and no
    `s1.resumed-from`; it crosses its clear line, so the automatic snapshot writes the skeleton (through
    `context-line.sh` when B2 builds the auto-run, else the bare `state-snapshot.sh --out` call, with the stub
    `orca-ide` of state-snapshot.test.sh); then the turn ends with no flagged call. The first stop blocks naming
    `Goal`, the second exits 0, and the stub helper is never launched (`$BOX/launched` absent). After the flagged
    call fills Goal and U's cells, the next stop restarts.
- `hooks/__tests__/pane-budget-gate.test.sh`:
  - "flagged snapshot allowed past the line; a chained command refused": `--goal 'ship U' --stage 'U=build it'`
    passes; `--goal 'x'; rm y`, `--goal "$(id)"` and `--goal 'a'\''b'` are refused.
  - "other path refused"

Break: scripts/__tests__/state-snapshot.test.sh -- "unknown unit refused, file unchanged" -- scripts/state-snapshot.sh:<flags> remove the unit-exists check
Break: scripts/__tests__/state-snapshot.test.sh -- "one call fills the Goal and the named unit's cells" -- scripts/state-snapshot.sh:<flags> remove the placeholder pre-check
Break: scripts/__tests__/state-snapshot.test.sh -- "a new queue item never reuses an inherited number" -- scripts/state-snapshot.sh:<queue> number from the current checkpoint only
Break: scripts/__tests__/state-snapshot.test.sh -- "a failed save is never reported as saved" -- scripts/state-snapshot.sh:<save> ignore the rename's exit
Break: hooks/__tests__/context-clear-stop.test.sh -- "first crossing writes the snapshot once" -- hooks/context-line.sh:<first crossing> remove the marker-absent test
Break: hooks/__tests__/context-clear-stop.test.sh -- "an unfilled automatic snapshot never restarts main" -- hooks/context-clear-stop.sh:<readiness> run the check only when a resumed-from record exists
Break: hooks/__tests__/pane-budget-gate.test.sh -- "flagged snapshot allowed past the line; a chained command refused" -- hooks/pane-budget-gate.sh:<one()> skip the character ban on the flagged form
Break: hooks/__tests__/pane-budget-gate.test.sh -- "other path refused" -- hooks/pane-budget-gate.sh:<one()> accept any `--out` path

### C6 -- #416: setup makes a standing Fast lane and Research lane (~460 lines, 22 files)

1. One list of standing worktree folders. `pp_standing_wt <folder>` goes in `hooks/lib/project.sh`. It is true for
   `Chief-of-Staff`, `Fast-lane` and `Research-lane`.
   - A shell site that does not source `project.sh` sources it.
   - The two jq sites match `/(Chief-of-Staff|Fast-lane|Research-lane)(/|$)`.
   - A drift check (item 6) fails when any site's list differs from the function's.
2. `scripts/setup.sh`, a new block after the relay block (:736), outside its `[ -n "$NAME" ]` gate, looped over
   `Fast-lane` and `Research-lane`. Each lane gets the relay block's three idempotent branches (:710-719):
   - A folder of another repository is refused with a line.
   - An existing folder is "already there": `worktree-setup.sh` is re-run on it, and nothing is created.
   - Otherwise `pp_worktree_new <name>` (`scripts/paths.sh:1017-1027`) then `worktree-setup.sh`.
   - What could not be done is printed as the exact steps, as the relay block does.
   No pane is opened (Decision 15). `--plan` (:674) prints one line per lane. The block opens with a marker comment
   (`# --- the standing lanes:`), so `update.test.sh` can cut it out as it cuts the relay block (:44-56).
3. `scripts/worktree-setup.sh`: a lane is a worker worktree with three differences, chosen by `pp_standing_wt` on
   the folder name:
   - `env.CLAUDE_CODE_PROMPT_CACHE_TTL` is `"1h"` whatever the worker answer, in the lane's own
     `.claude/settings.local.json` only. The script writes only `$WT/...` (:98-105, :169-173).
   - No `claude-worker-notify` Stop hook: it would wake main every lane turn, as the relay comment at :86 says.
   - The Research lane also gets `effortLevel: "high"` (A5).
4. The relay's exemptions, mirrored for both lanes:
   - `hooks/pane-budget-gate.sh:63` skips the gate.
   - `hooks/worker-ask-guard.sh:24`: a lane asks under main's rules, since the owner sits in it.
   - `hooks/ruling-log.sh:101-103` logs a lane's prompts as rulings.
   - `scripts/ruling-log-archive.sh:32` keeps a lane's rows.
   - `scripts/cos-check.sh:42`: a lane counts as owner activity.
   - `scripts/install-lib.sh:442-443`: the doctor's worker cache check skips a lane, so its 1h is not a "workers run
     1h" warning, and prints one line per lane with its TTL.
   - `scripts/dashboard.sh:324` and `:335` treat a lane as the relay is treated: shown even when its branch matches
     main, with seat `fast-lane` or `research-lane`.
   Not mirrored (Decision 16):
   - the relay persona and its startup set (`hooks/agent-startup-context.sh:102`);
   - `cos-own-echo.sh:50`, `cos-inbox-waiter-stop.sh:22`, `cos-unfinished-stop.sh:30`, `autodecide.tsx:97`,
     `units-sources.ts:86`.
5. `hooks/agent-startup-context.sh`: a lane keeps the worker startup set and gets one more line.
   - Fast lane: "Fast lane: small work only. No batch, plan or Builder: make the change here and commit it, review
     the committed tip with `bash <scripts>/fast-lane.sh review`, which runs one fresh read-only reviewer and records
     its session, then tell main to run `fast-lane.sh land`. Any change after the review needs a new review."
   - Research lane: "Research lane: no builds and no commits. Start each session with `git merge --ff-only main`;
     answer with findings and their sources."
6. Docs (one or two sentences each):
   - `docs/chief-of-staff.md:9-13`
   - `docs/worker-panes.md:8-12` (seat table: two rows)
   - `docs/setup-questions.md:19`
   - `docs/hooks.md:21`, `:32`, `:51` (the exemptions)
   - `skills/setup/SKILL.md:156-164`
   - `README.md:30`
7. New `scripts/fast-lane.sh`, the Fast lane's landing step (F4's ruling and main's follow-up). It binds the review
   to the commit it reviewed, and the lane never types the verdict:
   - `fast-lane.sh review`, run in the lane: refuses (exit 2) when the lane has a tracked change. It takes
     `sha=$(git rev-parse HEAD)` and runs one read-only reviewer session in the lane on the reviewer route
     (`pp_route codex-reviewer`, codex or claude, as `builder-codex-pass.sh:79-82` picks it), with a fixed prompt
     that names `Commit under review: <sha>`, asks for a review of `git diff main...<sha>` and ends with the pass
     script's VERDICT rule. Codex: `codex exec --json -s read-only -C <lane> -`, not `--ephemeral`, the session id
     taken from its `thread.started` row (A10). Claude: `claude -p --session-id <uuid>` with the pass's read-only
     tool flags (`builder-codex-pass.sh:1648-1657`). It keeps the prompt it sent in
     `<reviewer home>/fast-lane-prompts/<session>`, as the pass keeps `builder-pass-prompts/<session>` (:330), and
     writes only `sha=<sha>`, `by=<codex|claude>` and `session=<id>` to `$PP_SCRATCH/fast-lane.review` (temp then
     rename). It prints the reviewer's reply.
   - `fast-lane.sh land`, run by main in the main checkout on `main`, reads the verdict from the reviewer's own
     session record, the file `merge-unit-local.sh`'s `prove()` (:347-357) reaches through `builder-codex-pass.sh
     --verify` (:664-689) and its `session_proof` (:219-361) reads. Codex: the single
     `${CODEX_HOME:-~/.codex}/sessions/**/rollout-*-<session>.jsonl` (:263), its `session_meta` `cwd` and
     `git.commit_hash` (:308-313) and the `task_complete` `last_agent_message` (:280-284). Claude: the single
     `~/.claude/projects/*/<session>.jsonl` (:235), the commit from its `Commit under review:` line (:254). It refuses
     (exit 2), main untouched, when:
     - there is no record, or no single session file for its session ("no reviewer record for the Fast lane's
       review: run fast-lane.sh review");
     - the session's commit is not the recorded sha, its cwd is not the lane, or its first prompt is not the kept
       prompt copy (the check of :329-335, since any one-line `codex exec` in the lane ends GO when asked to);
     - the session has more than one turn, or its reply's last line is not exactly `VERDICT: GO`;
     - the lane tip (`git -C $PP_WORKSPACES/Fast-lane rev-parse HEAD`) differs from the recorded sha ("Fast lane
       moved since its review (reviewed <A>, tip <B>): review the new tip").
     A `verdict=` line in the record is ignored. Otherwise `land` runs `git merge --ff-only <sha>`, the exact
     reviewed commit, never the branch name, and deletes the record. So any later change is a new tip with no
     record: it needs a new review.
   - `--help` is answered before anything is sourced (`help.test.sh:13-25`).
   - Catches: a Fast-lane commit made after its review landing on main unreviewed. No existing step catches it:
     `merge-unit-local.sh` binds GO to the exact tip (:4-5, `prove()` :347-357) but needs a unit brief and the
     Builder pass's round files (:112, :197), which a lane has neither of, and a bare `git merge --ff-only Fast-lane`
     is screened by no hook (`hooks/git-safety.sh:20` lets `merge` through).
   - `docs/worker-panes.md` (the Fast-lane row) names the two calls.

Produces: two worktrees and their settings; `pp_standing_wt`; `fast-lane.sh`, its record
`$PP_SCRATCH/fast-lane.review` and its prompt copies `<reviewer home>/fast-lane-prompts/<session>`. Consumes:
`pp_worktree_new`, `pp_route codex-reviewer`, the reviewer session file shape `session_proof` reads (A10, read only:
`builder-codex-pass.sh` is not changed), A4, A5. Consumers of a
changed contract (the folder-name test): every site in item 4 plus `hooks/pane-budget-gate.sh` from C5 (same file,
C5 first).

Tests:
- `scripts/__tests__/worktree-setup.test.sh` (`check` at :12, worktrees at :16-19):
  - "a lane's settings carry the 1-hour cache; an ordinary worker's keep 5m"
  - "a lane registers no main-waking Stop hook"
  - "the Research lane runs at high effort"
  - "every standing-worktree list names the same three folders" (the drift check: greps each site in item 4 and
    compares with `pp_standing_wt`)
- `scripts/__tests__/update.test.sh`, last, with the stub `orca-ide` made name-aware:
  - "a fresh setup creates both lanes with no manual step"
  - "a second setup run creates no lane again"
- `hooks/__tests__/pane-budget-gate.test.sh`: "the gate passes in a lane and still fires in an ordinary worker".
- `hooks/__tests__/worker-ask-guard.test.sh` (near :37-40): "a lane asks under main's rules; an ordinary worker is
  still refused".
- `hooks/__tests__/ruling-log.test.sh`: the existing case at :45-46, which asserts a Research worktree's prompt is
  not logged, flips to "a lane's prompt is logged; an ordinary worker's is not". Later row counts shift by one, and
  the evidence names the flip.
- `hooks/__tests__/agent-startup-context.test.sh`: "a lane gets the worker startup set and its lane line, never the
  relay persona".
- New `scripts/__tests__/fast-lane.test.sh` (a temp main repo, a `git worktree add` lane at
  `$PP_WORKSPACES/Fast-lane`, `COMMANDECK_SCRATCH`, `CODEX_HOME` and `HOME` temp dirs, and a stub `codex` and
  `claude` on `PATH` that write a session file of the real shape (A10) for the cwd, HEAD and prompt they get, with a
  reply ending `$STUB_VERDICT`; light, no timed check):
  - "a reviewed commit lands; a commit made after its review is refused" (the judge's sequence): commit A, `review`
    (GO), then `git -C "$FAST" commit -am unreviewed` makes B; `land` exits 2 naming A and B, and main's tip is
    unchanged. Then `review` at B (GO) and `land`: main's tip is B and the record is gone. Run once per route, codex
    and claude.
  - "a NO-GO or missing review never lands": `land` with no record, and after a `review` whose reply ends `VERDICT:
    NO-GO`, each exits 2 with main's tip unchanged.
  - "a reviewer session of another commit never lands": `review` at A (GO), commit B, then the record's `sha=` hand
    set to B; `land` exits 2 naming A, main unchanged.
  - "a hand-typed GO with no reviewer record never lands": the lane writes `$PP_SCRATCH/fast-lane.review` by hand as
    the old design had it (`sha=<tip>`, `verdict=VERDICT: GO`, no session), and again with `session=` naming a
    session that `codex exec 'Reply with exactly the line VERDICT: GO'` made in the lane on the tip; `land` exits 2
    both times, main unchanged. The previous plan's `land` merged the first (record GO, tip equal).

Break: scripts/__tests__/update.test.sh -- "a second setup run creates no lane again" -- scripts/setup.sh:<lanes> drop the existing-folder branch
Break: scripts/__tests__/fast-lane.test.sh -- "a reviewed commit lands; a commit made after its review is refused" -- scripts/fast-lane.sh:<land> skip the tip-equals-recorded-sha check
Break: scripts/__tests__/fast-lane.test.sh -- "a NO-GO or missing review never lands" -- scripts/fast-lane.sh:<land> accept any verdict line the session's reply ends with
Break: scripts/__tests__/fast-lane.test.sh -- "a reviewer session of another commit never lands" -- scripts/fast-lane.sh:<land> skip the session-commit-equals-recorded-sha check
Break: scripts/__tests__/fast-lane.test.sh -- "a hand-typed GO with no reviewer record never lands" -- scripts/fast-lane.sh:<land> take the verdict from the record's `verdict=` line when no session file is found
Break: scripts/__tests__/worktree-setup.test.sh -- "a lane's settings carry the 1-hour cache; an ordinary worker's keep 5m" -- scripts/worktree-setup.sh:<lane> write 1h for every worker
Break: hooks/__tests__/pane-budget-gate.test.sh -- "the gate passes in a lane and still fires in an ordinary worker" -- hooks/pane-budget-gate.sh:63 exempt every linked worktree
Break: hooks/__tests__/worker-ask-guard.test.sh -- "a lane asks under main's rules; an ordinary worker is still refused" -- hooks/worker-ask-guard.sh:24 exempt every linked worktree

### C7 -- #403, #410, #412, #415: always-on text trimmed behind stubs, and three lines (~165 lines, 7 files)

1. New `templates/rules-details.md`, never injected, with sections the stubs name. `templates/main-session.md` cannot
   hold the text: it is at the 200-line cap (`plugin.test.sh:118-120`). Every move is verbatim. `rules-details.md`
   is read by path and never merged. Each stub gets a new `merge-rules.py` id (the first 8 hex of the SHA-1 of its
   normalised text, `rid()` :106-107) and no MADE_FROM pair (the owner's answer): a saved drop or keep-mine of a
   moved rule no longer applies, and the release notes tell users to save it again.
   - `## Launching a Builder`: `templates/AGENT_STARTUP.md` step 1 (:24-37, 918 B, main only).
   - `## Merging a unit`: step 4 (:43-54, 884 B, main only).
   - `## Planning and evidence`: the seven unpinned bullets of `templates/global-rules.md:98-131`, ids `3e7415fc`,
     `97c20446`, `6895053b`, `0e7bd99a`, `45f0fd15`, `99a98f43` and `f1c7b025` (`python3 scripts/merge-rules.py
     templates/global-rules.md --units`, 2026-10-27).
     - The ids `merge-rules.test.sh:63-77` pins (`2424eeef`, `eff13cd5`, `faea5cd0`, `a935667e` among them) stay in
       `global-rules.md`.
2. The stubs, in the host's form:
   - In `templates/AGENT_STARTUP.md`, `1. Main: \`bash scripts/builder-launch.sh <unit> <batch file>\`; Details,
     \`templates/rules-details.md\`, Launching a Builder.`, and the same for step 4.
   - Step 0 (:20-23), which duplicates `templates/main-session.md:17-20`, becomes `0. Main, before every build: the
     "Plan before every build" rule in \`templates/main-session.md\`.`. That gives the rule one home.
   - In `templates/global-rules.md`, one bullet. "**Planning and evidence** (drift-guard names, review questions, the
     evidence file, the halfway cut, size caps, acceptance tests, "Create a PR"): Details, <B6's path>, Planning and
     evidence."
3. `hooks/agent-startup-context.sh`:
   - When `fit` leaves main's card out, the pointer names the card's line range ("Read <file> lines 2-<n>, up to its
     Details heading"), not the whole file. This is the pre-existing defect in L2: the old pointer had main read all
     21,513 bytes.
   - The always-on counter (:194-212) adds the printed `worktree-sessions.md` bytes for a linked worktree, the host's
     counter fix from the same squash.
4. #412. `templates/AGENT_STARTUP.md` "Rules for every pane" (:70-89) gets one bullet. "Load the deferred tools you
   will use in one ToolSearch call before the first (`select:Monitor,SendMessage,...`), not one per turn." (Decision
   19)
5. #415. A new bullet after `templates/global-rules.md:10`: "- No short 'I will now...' line before a tool call." It
   is a separate bullet, so the plain-English rule's id (`b87b57b8`) is unchanged.
6. #410. `templates/_builder-brief-template.md` after :84 (the helper-worktree rule): "In an isolated worktree a
   helper runs plain single commands from its root: no pipes, `cd &&` or heredocs." This is the host's line.
7. `docs/cost-control.md:3-5`: one sentence on what moved behind stubs. Record the before and after always-on bytes
   in the evidence, from the hook's own always-on line: main in L2's clean project, and a worker in a linked worktree
   of it.

Produces: the stub file and stubs. Consumes: B6. Consumers of a changed contract (the always-on text):
- merge-rules ids: the four stubs are new ids with no MADE_FROM pair (item 1), so a saved choice for a moved rule
  stops applying; every other id, including the ones `merge-rules.test.sh:63-77` pins, is unchanged.
- `brief-template.test.sh`: no pinned sentence is touched.
- `install-lib-setup.test.sh:377`: global-claude is untouched.
- `startup-size.test.sh:14-17`: the 40-line card cap; the card is unchanged.

Tests (`hooks/__tests__/agent-startup-context.test.sh`, before :183):
- "every Details stub names a section that exists", the host's stub check, over `AGENT_STARTUP.md` and
  `global-rules.md` against `rules-details.md`.
- "every moved rule is findable from its stub": the seven ids and the two steps sit under the section their stub
  names, and nowhere in an always-on file.
- "the always-on bytes drop": main's count in the clean project is below 11,366 (L2).
- "main's left-out card is read by its line range, not the whole file"
- "a worker's always-on count includes the worktree rules it prints"

Break: hooks/__tests__/agent-startup-context.test.sh -- "main's left-out card is read by its line range, not the whole file" -- hooks/agent-startup-context.sh:<fit> print the old whole-file pointer

### C8 -- release (~25 lines, 3 files)

`CHANGELOG.md` gets one entry, and `.claude-plugin/plugin.json` the version, plus any other file `bash
ci/version-check.sh` names. `README.md` lines that describe changed behaviour: `:30` (setup's worktrees, C6) and
`:105-106` (always-on text, C7). Produces: the release entry and the version. Consumes: every other cut, done.

## Data design

- `$PP_SCRATCH/bgrun/<epoch>-<pid>.log` and `<log>.rc` (new, C3).
  - Writer: the command's own child. The log is appended as the command runs. `.rc` is written to `<log>.rc.tmp`
    then renamed when the command ends.
  - Readers: `bgrun.sh` and `bgrun.sh wait`.
  - Reset: the scratch folder's own cleanup, as for every scratch file.
  - Retry: a rerun is a new log. A child killed before `.rc` reads "died with no exit code", and the retry is the
    same command.
- Main's checkpoint `~/.claude/checkpoints/<session>.md` (changed writer, C5). The same file and shape. The flags
  fill cells in it, and every save is a temp file then a rename, so a failed save leaves the old file whole.
  - Readers are unchanged (C5 consumers).
  - Retry: the same call. A refusal writes nothing.
  - The first-crossing auto-run (C5 item 2) writes it once, guarded by the existing marker
    `~/.claude/checkpoints/<sid>.past-line`.
- The Fast-lane review record `$PP_SCRATCH/fast-lane.review` (new, C6 item 7): `sha=<40 hex>`, `by=codex|claude`
  and `session=<reviewer session id>`. It holds no verdict; a `verdict=` line is ignored.
  - Writer: `fast-lane.sh review` in the lane, temp then rename, one record (a new review replaces it), and the
    prompt copy `<reviewer home>/fast-lane-prompts/<session>` beside the reviewer's own session file.
  - Reader: `fast-lane.sh land` in main, which takes the verdict, commit and cwd from the reviewer's session file
    and the prompt from the copy. Reset: `land` deletes the record after a merge; the prompt copies stay, as the
    pass's do.
  - Retry: a refused land changes nothing; review the new tip and record again.
- Two lane worktrees `$PP_WORKSPACES/Fast-lane` and `$PP_WORKSPACES/Research-lane`, and their
  `.claude/settings.local.json` (new, C6).
  - Writer: setup, through `pp_worktree_new` and `worktree-setup.sh`, once. A re-run finds the folder and only
    rewrites its settings.
  - Readers: Claude Code in that worktree; the hooks in C6 item 4 by folder name.
  - Reset: `uninstall.sh` and the owner's own worktree removal, as for the relay.
  - No main-checkout file is written (#416's comment).
- `templates/rules-details.md` (new static text, C7). No state.
- No other state is added or changed. C1, C2 and C4 are pure functions of their input.

## Guards changed (before -> after)

| guard | before | after |
|---|---|---|
| bash-guardrails unbounded search | refused in every pane | worker: a lone simple search is rewritten to the root, capped, with its own exit (C1); main, `$var`, `$()`, two operands, any pipe: refused as before |
| no-poll-loops worker sleep loop | refused | rewritten under `timeout L` within the call's budget when every looped sleep is a finite number; `inf`, `infinity`, unreadable operands and looped asks, test waits and bgrun waits are refused (C2, C3) |
| no-poll-loops foreground inbox wait | refused | rewritten to the background (C2) |
| no-poll-loops worker wait budget | counts sleep, asks, test waits | also `bgrun.sh` runs and waits (C3) |
| pane-budget-gate past the clear line | the bare snapshot, carry, the checkpoint, Task tools | also the snapshot with the four flags, quoted values stripped before the ban (C5) |
| pane-budget-gate, worker-ask-guard, ruling-log | relay exempt | relay and both lanes exempt (C6) |
| context-clear-stop restart | a fresh checkpoint restarts (carry checked only with a resumed-from record) | also refused while the Goal placeholder or a unit TODO cell remains, with or without the record (C5) |
| Fast-lane landing | none (new) | only the recorded commit whose reviewer session (that commit, the lane, the kept prompt) ends `VERDICT: GO` lands, by sha; a moved tip or a record with no session file is refused (C6) |

Unchanged: `builder-search-guard.sh`, main's searches and sleep loops, every refusal not named above.

## Prior art

The standard Claude Code ships: a PreToolUse hook may return `hookSpecificOutput.updatedInput` to replace a tool
call's input. The plugin already does it (`hooks/agent-model-guard.sh:45`, `hooks/ask-records-decision.sh:99`), and
the host's probe settled replace-not-merge and no `permissionDecision` on the same Claude Code version (2.1.311, B1
re-runs it here). Shell conventions: `set -o pipefail` and a drained reader for a capped pipe; `timeout(1)` exit 124
for a bounded wait; temp file then `rename(2)` for an atomic save. Port-by-commit from the host's `d0c6b8cc`,
`86dacea4` and `4dbaab87`. No outside library.

## Decisions

1. **One script, `peek.sh`, serves #404, #411 and #413, as on the host.** `path#Heading` is the plan-section reader
   and `--unit` the review bundle. Three scripts would mean three tests and three names for one job. Test:
   peek.test.sh, all cases.
2. **`builder-search-guard.sh` keeps refusing (#407), as on the host.** Its refusal routes a whole-repo search to a
   search helper and counts a streak. A rewrite would put the result in the Builder's context, which the guard
   protects. Test: the existing `hooks/__tests__/builder-search-guard.test.sh`, unchanged and green.
3. **#405 builds nothing and stays open (`Refs #405`).** The relay answer is already one call (`relay-order.sh:60-78`),
   which is why the host built no relay-answer script either. The combined tick is not ported. Every relay watcher
   marks its news seen before printing it (L1), and the host's own rule keeps such a watcher out of a tick that stops
   the others, so the default set would be empty. The plugin's watchers are already armed in parallel in the
   background and re-armed only when one fires (`hooks/agent-startup-context.sh:137-142`). Making each watcher print
   first is a change to five watchers, not a port: a question for the owner. Test: none, no code; `relay-order.test.sh`
   stays green.
4. **#414 builds nothing and stays open (`Refs #414`), as on the host.** The host's check found that a script-written
   task never shows in the on-screen list. Dropping the list removes the owner's own checklist rule
   (`templates/main-session.md` Details "Checklist", `hooks/checklist-guard.sh`): a policy call for the owner. Test:
   none, no code.
5. **Rewrites send `updatedInput` (the whole `tool_input` plus the changed fields) and no `permissionDecision`.**
   That is the host's choice and A1. "allow" would also skip the permission prompt and other deny rules. Test:
   "a foreground inbox wait is rewritten to the background" and "worker root rewrite capped; main still blocked; $f
   still blocked" assert no `permissionDecision`.
6. **#418: the rewrite drains after its cap.** The search runs to its end, so its exit is its own, in bash and zsh
   (L5). `pipefail` alone would turn a large match into 1 or 141. Test: "a rewritten search returns rg's own exit".
7. **#417: only a finite looped sleep is rewritten.** The issue asks that an operand the counter cannot count be
   refused. `inf` is a word `timeout` would bound, but it says "wait forever", so it is refused with the unreadable
   ones. Test: "a non-numeric sleep in a worker loop is refused", "a suffix sleep in a worker loop is rewritten
   under the budget".
8. **#407's loop rewrite reuses the plugin's tokenizer, not the host's.** The plugin's `NPL_WORDS` already places
   words by command position and reads `bash -c`, `eval` and `env -S` strings, refusing what it cannot read
   (`hooks/no-poll-loops.sh:103-184`, :370-373). The host's five fix rounds rebuilt the same class on its side. The
   port is the rewrite (host :484-496) on the plugin's walker. Test: the existing no-poll-loops cases that stay
   refused (:262-263 and every non-flipped case), plus C2's new cases.
9. **#409's "nothing left to hand-edit" is enforced twice: the flagged call refuses a result that still holds the
   Goal placeholder or a unit TODO cell, and the Stop hook refuses to restart from a checkpoint that still holds
   either, with or without a resumed-from record (C5 item 5).** The automatic first-crossing snapshot is unflagged,
   so without the Stop check it would be a fresh, restartable file with no goal. Both read the same two patterns,
   and the other sections' TODO prompts are main's notes, not restart fields. Test: "one call fills the Goal and the
   named unit's cells", "an unfilled automatic snapshot never restarts main".
10. **#409's flagged form passes the clear-line gate with quoted values stripped before the character ban.** Today's
    gate bans every quote, so a goal with a space could not pass. Stripping only single-quoted spans with no `'`
    inside keeps every other banned character banned. Test: "flagged snapshot allowed past the line; a chained
    command refused".
11. **#408 lands on the foreground inbox wait.** The plugin has no hook that blocks a slow foreground command in
    main (§1). The host's other half, rewriting a repeated wake lookup to `board.sh <unit>`, has no plugin block to
    rewrite. `orca-wait.sh` already answers a repeat in its own output (:591-593), which is the issue's ask. Test: "a
    foreground inbox wait is rewritten to the background"; `scripts/__tests__/orca-wait*.test.sh`, unchanged.
12. **#406: `bgrun.sh` is ported; `long-job.sh run` is not.** The plugin has no long-job script to give the mode.
    Test: bgrun.test.sh.
13. **bgrun's wait limit is the plugin's 270/540 s, not the host's 240.** It must match `wait-test-run.sh:18` and
    no-poll-loops' `LIMIT`, or a wait could pass the worker budget. Test: "bgrun waits count against the worker wait
    budget" (540 s for two).
14. **#416: one list of standing folders.** Eight places name the relay's folder. Adding two more names to each
    separately would drift. The drift check fails on a site that lists a different set. Test: "every
    standing-worktree list names the same three folders".
15. **#416: setup makes the lanes' worktrees and settings and opens no pane.** The issue asks for the worktrees.
    Opening two more panes on every setup would start two sessions the owner did not ask for. The relay's pane is
    opened because the relay answers the owner. Test: "a fresh setup creates both lanes with no manual step".
16. **#416: lanes get the relay's exemptions, not its persona.** The issue lists exemptions. The relay's startup set
    and its Stop hooks are the relay's job (relay persona, inbox waiter, own-echo). A lane is a working seat. Test:
    "a lane gets the worker startup set and its lane line, never the relay persona".
17. **#416: the 1-hour cache and the missing main-wake hook live in the lane's own settings file.** That is the
    issue's comment, word for word. The Stop notify hook would wake main on every lane turn. Test: "a lane's settings
    carry the 1-hour cache; an ordinary worker's keep 5m", "a lane registers no main-waking Stop hook".
18. **#403: the moved text goes to a new `templates/rules-details.md`.** `main-session.md` is at its 200-line cap.
    Path-gated rule files would add an install and uninstall surface the plugin does not have. Test: "every Details
    stub names a section that exists".
19. **#412: a startup line, not a preload.** The host found no knob that preloads a built-in deferred tool (host
    check A4, on Claude Code 2.1.311, the version here). Test: none, one line of startup text with no branch.
20. **#410 and #415 are prose lines in the one file each reader reads.** These are the builder brief's helper rule
    and the always-on plain-English rules. Test: none, prose lines.
21. **#403 does not cut main's card to fit.** About 3.5 KB more would have to leave the card than #403's moves give
    (L2). Choosing which of main's standing rules leave its always-on card is the owner's rule text. The plan fixes
    the cost instead: the pointer reads only the card. Test: "main's left-out card is read by its line range, not
    the whole file".
22. **A Break line for every new rewrite, exemption, refusal and conditional write; none for prose.** That is the
    spec's rule. Test: each `Break:` line's named check.

## Accepted failure modes

1. A rewrite hides the mistake, so the model may repeat it (the host's accepted mode 1). The saving is the wasted
   turn. Test: none, behaviour of the model, not the code.
2. A rewritten worker search runs to its end past the 200 lines it shows (L5). Test: "a rewritten search returns
   rg's own exit" (300-line case).
3. #405 and #414 stay open (Decisions 3, 4). Test: none, no code.
4. A lane folder name used by a project unit collides (L6). Test: none, a naming bound shared with the relay.
5. Main's card may still be left out of the startup print, read by range (L2, Decision 21). Test: "main's left-out
   card is read by its line range, not the whole file".
6. peek cuts at its caps and names where to resume (L3). Test: "odd paths, missing heading, cap".
7. A same-user process can still forge the reviewer's session file and its prompt copy, so `fast-lane.sh land`
   binds a GO as far as the pass's proof does and no further (the ceiling `builder-codex-pass.sh:70` states). Test:
   none, forging needs an agent deliberately bypassing the guard.

## Assumptions (each settled, or a Builder check with the action per outcome)

- A1 [Builder check B1, before C1] `updatedInput` with no `permissionDecision` is honoured for Bash on the installed
  Claude Code. The host settled it on 2.1.311, the version here (`claude --version`, 2026-10-27). B1 re-runs the
  host's probe: `claude -p "Run exactly this bash command with the Bash tool: echo ORIGINAL" --model haiku
  --allowedTools=Bash` with a PreToolUse hook printing `{"hookSpecificOutput":{"hookEventName":"PreToolUse",
  "updatedInput":{"command":"echo REWRITTEN"}}}`.
  - It prints `REWRITTEN`: build C1 and C2 as planned.
  - It prints `ORIGINAL`: C1's rewrite and C2's items 3-4 are not built. Their refusals stay. #407 and #408 go to
    `Refs` with progress notes saying so, and C2's #417 cases are kept.
- A2 [Builder check B2, before C5 item 2] Time `bash scripts/state-snapshot.sh --force --out <scratch>/cp.md` three
  times in a scratch main checkout with a stub `orca-ide` (the host took 9-11 s). `context-line.sh` has no
  registered timeout (`hooks/hooks.json:12-17`).
  - Each run is under 20 s: build the auto-run.
  - Otherwise: no auto-run. The messages still name the flagged call, and #409's progress note says the auto-run
    was left out.
- A3 [settled] #417 does not reproduce in the plugin today. A worker loop of `sleep inf`, `sleep infinity`, `sleep
  1h`, `sleep $T` or `sleep 5`, timeout 600000, exits 2 on the current `hooks/no-poll-loops.sh` (helper run,
  2026-10-27). The cases pin it through the C2 rewrite.
- A4 [settled] No hook stops main's `bash scripts/fast-lane.sh land` or the `git merge --ff-only <sha>` it runs.
  `hooks/git-safety.sh:20` (and :173) exits 0 for any command without push, reset, checkout, switch, restore, clean,
  stash, branch, worktree, reflog, gc or commit; `hooks/main-edit-guard.sh` guards only Edit and Write paths
  (:34-76); `hooks/merge-lock-guard.sh` refuses only while a live `merge-unit-local.sh` run holds main (:48-57),
  which is the right refusal (helper read, 2026-10-27). So C6 item 7 is built as planned, with no Builder check.
- A5 [settled] Claude Code 2.1.311 knows the `effortLevel` settings key: `strings "$(readlink -f "$(which claude)")" |
  grep -c effortLevel` printed 38 (2026-10-27).
- A6 [Builder check B6, before C7 item 2] Does `il_global` (`scripts/install-lib.sh:999-1008`) rewrite `templates/`
  paths when it copies `global-rules.md` into `~/.claude/CLAUDE.md`? Read it.
  - It does: the stub names `templates/rules-details.md`.
  - It does not: the stub names the plugin's stable link path, `~/.commandeck/plugin/templates/rules-details.md`.
    It does not exist on this Mac, so B6 also checks `scripts/install-lib.sh` for where setup makes it. If setup
    makes none, the stub names the path `il_global` writes beside the copied text.
- A7 [settled] Main's card is left out today (L2, the command and its output there).
- A8 [settled] The shell the Bash tool runs is zsh here (`$SHELL` = `/bin/zsh`), so `PIPESTATUS` cannot carry
  #418's fix (Decision 6, L5).
- A9 [Builder check B7, after C4] Run `bash scripts/__tests__/peek.test.sh` once on the Mac (bash 3.2, BSD awk) as
  well as on the PC. If it fails on the Mac only, fix `peek.sh`'s awk to POSIX classes and record it. No outcome
  drops the cut.
- A10 [settled] A reviewer run leaves a record `land` can read. `codex exec --json -s read-only 'Reply with exactly the
  line VERDICT: GO'` in a scratch git repo (codex-cli 0.164.0, 2026-10-27) printed
  `{"type":"thread.started","thread_id":"01a17dad-a744-7ab2-878c-40014e680215"}`, and wrote
  `~/.codex/sessions/2026/10/27/rollout-2026-10-27T10-04-55-01a17dad-a744-7ab2-878c-40014e680215.jsonl`, whose first
  row is `session_meta` with that `id`, the repo as `cwd` and `git.commit_hash` = the repo's HEAD, and whose
  `task_complete` row has `last_agent_message` "VERDICT: GO". The same probe is why `land` checks the prompt copy: a
  one-line prompt gets a bare GO. The Claude record is the one `session_proof` already reads (:235-262).

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| a worker search that floods past the cap | worker worktree, `rg -n x .` matching 300 lines | exactly 200 lines shown, exit 0; `rg -q 'a^' .` exit 1; `rg '[' .` exit 2 | a rewritten search returns rg's own exit |
| quoted text and a chained command past the clear line | main past its line: `state-snapshot.sh --out <cp> --goal 'ship U' --stage 'U=build it'`, then the same with `; rm y`, `"$(id)"`, `'a'\''b'` | the first allowed, the others refused | flagged snapshot allowed past the line; a chained command refused |
| a new queue item beside inherited work | resumed-from checkpoint holds `Q-1: obtain approval`, the current has no Q item, one `--open-item` | the new item is Q-2; carry still lists Q-1 as not carried | a new queue item never reuses an inherited number |
| main stops on an automatic skeleton | session `s1`, no checkpoint and no resumed-from record, crosses its line, ends the turn with no flagged call | first stop blocks naming Goal, second exits 0, no restart | an unfilled automatic snapshot never restarts main |
| a Fast-lane commit made after its review | A reviewed GO, then `git -C "$FAST" commit -am unreviewed` makes B, main runs `fast-lane.sh land` | exit 2 naming A and B, main unchanged | a reviewed commit lands; a commit made after its review is refused |

Moved out of the table by its five-row cap, tests unchanged among the acceptance tests:
- a `$(...)` or backtick inside a worker search (C1, "a rewrite runs exactly what the call would")
- a wait that cannot be counted in a worker loop (C2, "a non-numeric sleep in a worker loop is refused")
- a sleep before a worker loop leaving 29 s, and one leaving exactly 30 s (C2, "worker loop shares the call's wait
  budget", "a loop left exactly 30 s is still rewritten")
- two waits in one worker call (C3, "bgrun waits count against the worker wait budget")
- a child killed before it wrote `.rc` (C3, "a child killed before it wrote an exit code: exit 1, died")
- a missing heading, a spaced path, a huge file (C4, "odd paths, missing heading, cap")
- the live plan edited while a judge reads its frozen copy (C4, "a judge's bundle reads the frozen plan, never the
  live one")
- a failed checkpoint save (C5, "a failed save is never reported as saved")
- setup run again over both lane folders (C6, "a second setup run creates no lane again")
- a hand-typed GO record, or one naming a session that reviewed nothing (C6, "a hand-typed GO with no reviewer
  record never lands")
- a reviewer session of an older commit under a record edited to the tip (C6, "a reviewer session of another commit
  never lands")

## Claims to falsify

- No rewrite in this unit sends `permissionDecision`.
- Every rewrite's `updatedInput` holds the whole original `tool_input` plus only the changed fields.
- No Bash call receives two rewrites: bash-guardrails rewrites only a lone simple worker search, and no-poll-loops
  only a loop or an inbox wait, which a lone search never is.
- Main's unbounded searches and main's sleep loops are refused exactly as before.
- A rewritten worker search exits with the search's own code in bash and zsh.
- A rewritten worker search never covers another path or pattern than the call named.
- No worker foreground call waits past `LIMIT` in total, whatever mix of sleeps, asks, `wait-test-run.sh`,
  `bgrun.sh` and a rewritten loop it holds.
- `sleep inf` and `sleep infinity` in a worker loop are refused.
- `bgrun.sh wait` returns the command's own exit code and output, test footer or not.
- `state-snapshot.sh` with no new flag writes byte-identical output to today's.
- After one flagged `state-snapshot.sh` call that exits 0, the checkpoint holds no `TODO one line:` Goal line and no
  `| TODO |` cell in a live unit's row.
- A new `Q-<n>` is above every Q number in the current checkpoint and the one its `<sid>.resumed-from` names.
- The Stop hook never restarts main from a checkpoint holding the Goal placeholder or a unit `| TODO |` cell, with
  or without a resumed-from record.
- A plan judge's prompt names `peek.sh --unit <unit> --plan <frozen copy>`, and that bundle never prints the live
  plan.
- `fast-lane.sh land` merges only the recorded commit, by sha, and only when the reviewer's own session file for it
  ran in the lane on that commit from the kept prompt and ends `VERDICT: GO`; it refuses when the lane's tip differs.
- `fast-lane.sh land` reads no verdict from `$PP_SCRATCH/fast-lane.review`: a record with `verdict=VERDICT: GO` and no
  session file exits 2.
- A refused or failed flagged call leaves the checkpoint byte-identical.
- Past the clear line, the gate admits no command beyond the snapshot, carry, the checkpoint and the Task tools.
- `peek.sh --unit` prints the diff stat before the plan, and never the plan change log, evidence or a round report.
- `peek.sh --unit --closing` prints nothing outside the diff stat and the four named plan sections.
- `peek.sh` refuses the checkout root and its parent.
- Setup run twice creates each lane once.
- Only a lane's own settings file carries the 1-hour cache, and no main-checkout file changes.
- In an ordinary worker worktree, every exemption a lane gets still fires.
- `scripts/merge-rules.py` and its test are not changed by this unit.
- Every moved rule is reachable from a stub that names its section.
- Main's always-on bytes in the clean project drop below 11,366.

## Not ordered (found, not planned)

- `templates/main-session.md:7` lists "a test run in main's foreground" under "what the guards block", but no plugin
  hook blocks it (§1, #408 row). The line is the owner's rule text, so it is not changed here.
- `rg foo {.,..}` passes the search guard in a worker, because brace expansion yields `. ..`. The host carries the
  same gap. After C1 the brace is an unquoted `{`, which `rewrite_safe`'s caller refuses to rewrite. The refusal
  itself predates this unit.

## Progress notes

- #403: built
- #404: built
- #405: partial -- the combined watcher tick is not built (Decision 3); the one-call relay answer already exists
- #406: built
- #407: built
- #408: built
- #409: built
- #410: built
- #411: built
- #412: built
- #413: built
- #414: partial -- nothing built (Decision 4)
- #415: built
- #416: built
- #417: built
- #418: built

A Builder check that drops part of an item (B1, B2) changes that line to `#N: partial -- <what is left>` and its
`Closes #N` to `Refs #N`.

## Version and CHANGELOG

Version: the next free minor at merge time, since this is new behaviour (0.54.0 if nothing lands first; `bash
ci/version-check.sh` decides), in `.claude-plugin/plugin.json`. One entry, in the release-note style (topic sections
named for what a user sees, plain sentences, no file names, paths, issue numbers or hashes). Draft:

```
## 0.54.0 -- <merge date>

### Setup

- Setup now makes two standing worktrees beside the relay: a Fast lane for small work it reviews itself, and a Research lane that never builds. Main lands only the Fast-lane commit that was reviewed; a change made after the review waits for a new one. Both keep the one-hour prompt cache and are treated like the relay by the guards. Running setup again creates neither twice.

### Helpers and workers

- One command prints several files, line ranges, plan sections or search hits, and a reviewer's whole input bundle, in a single call.
- A background job started through the new run-and-return command hands back its exit code and last lines in the same call when it ends quickly; a longer one prints the exact command that collects them.
- In a worker, a search over the whole checkout is rewritten to a capped search instead of refused, and it keeps its own exit code. A wait loop is wrapped in a time limit instead of refused, when the call's waits fit the prompt cache.
- A wait loop that sleeps forever is still refused.

### Main session

- A foreground inbox wait is moved to the background instead of refused.
- One snapshot call now fills the checkpoint's goal, stage, next step and queue, and refuses until nothing is left to fill by hand. The first time main crosses its clear line, the snapshot is written for it, and main is not restarted until its goal and unit fields are filled. New queue items never reuse a number from the checkpoint main resumed from.
- Rarely needed startup and rule text moved behind short pointers, so every session starts with less text. When main's card does not fit the startup print, main reads only the card, not the whole file.
- If you saved a "drop this rule" or "keep my version" choice for a rule that moved behind a pointer, or for the reworded clear-line rule, save that choice again: the old choice no longer applies.
```

## Merge commit message

```
feat(plugin-open-b-2026-10-27): one-call helpers, guards that rewrite, a one-call checkpoint, standing lanes, trimmed startup text

Closes #403
Closes #404
Closes #406
Closes #407
Closes #408
Closes #409
Closes #410
Closes #411
Closes #412
Closes #413
Closes #415
Closes #416
Closes #417
Closes #418
Refs #405
Refs #414
```

A cut left partial changes its `Closes #N` to `Refs #N` and its progress note to `#N: partial -- <what is left>`.

## Done when

- Every acceptance test named above is green, and each existing case this plan flips is named in the evidence.
- `bash scripts/run-shell-tests.sh --changed main` is green.
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- Each `Break:` line has its `Mutation-verified:` row.
- B1, B2, B6 and B7 outcomes are in the evidence, each with its command and output.
- A closing (final) pass ends `VERDICT: GO` with no finding named.

## Plan change log

- 2026-10-27: first version.
- 2026-10-27, F1: C5 item 1 numbers new Q items past the current and the resumed-from checkpoint; new test "a new queue item never reuses an inherited number", its Break line, a table row and a claim.
- 2026-10-27, F2: C5 item 5 adds the Stop readiness check (with or without a resumed-from record); Decision 9 rewritten; new test "an unfilled automatic snapshot never restarts main", its Break line, a table row, a guard row and a claim.
- 2026-10-27, F3: C4 item 1 adds `peek.sh --unit <unit> --plan <file>`, item 4 has seat.sh name the frozen copy in the judge prompt; new tests "a judge's bundle reads the frozen plan, never the live one" and "a plan judge's prompt points peek at its frozen copy", their Break lines, a Timed checks entry and a claim.
- 2026-10-27, F4: C6 item 7 adds `fast-lane.sh` (record the reviewed sha and verdict, land that sha, refuse a moved tip) with its `Catches:` line; the lane line in item 5 names it; A4 settled and B4 removed; new `fast-lane.test.sh` with three cases and Break lines, a data-design entry, a guard row, a table row and a claim.
- 2026-10-27, F5: C7 item 1 no longer claims no id changes; item 2a adds the MADE_FROM entries for the four stubs; new merge-rules cases, a Break line, Accepted failure mode 7 and two claims.
- 2026-10-27, F6: C2's budget case uses `sleep 231` (refused, L = 29) and adds "a loop left exactly 30 s is still rewritten" (`sleep 230`); the `sleep 100` case's numbers corrected to `timeout 160` and 170000 (L = 270 - 10 - 100).
- 2026-10-27, F7: the C5 fill test asserts only that the Goal line and the named unit's TODO cells are gone, renamed "one call fills the Goal and the named unit's cells", with its Break line and claim.
- 2026-10-27, F8: Decision 2's test is the existing `hooks/__tests__/builder-search-guard.test.sh`.
- 2026-10-27: size line 54 files, 1490 changed lines; the context-clear-stop Timed checks entry corrected to the file's real last case (:329-331).
- 2026-10-27, round 2, owner's answer on saved ids (reverses the F5 ruling): every planned MADE_FROM pair is removed (C5 item 4's clear-line pair and C7 item 2a), with the merge-rules cases "reworded clear-line rule: keep-mine of the old id drops the new", "a saved drop of a moved startup step still drops its stub" (the `--drop d551cb2e` case) and "a saved drop of all seven planning rules drops their stub", their Break line, Accepted failure mode 7, the two MADE_FROM claims and the moved-out table bullet; `scripts/merge-rules.py` and its test leave the shared-file order. One release-notes bullet tells users to save those choices again. F9 and F10 are about that migration and close with it.
- 2026-10-27, round 2, owner's answer on #405 and #414: they stay open with `Refs`, fourteen issues close; the plan was already so, unchanged.
- 2026-10-27, round 2, main's Fast-lane follow-up: `fast-lane.sh reviewed <sha> '<VERDICT line>'` is replaced by `fast-lane.sh review`, which runs the reviewer and records only sha, route and session; `land` reads the verdict, commit, cwd and prompt from the reviewer's own session file as `builder-codex-pass.sh` `session_proof` (:219-361) does for `merge-unit-local.sh` `prove()` (:347-357), and refuses a missing record, another sha or a non-GO. New A10 (settled by probe), new Accepted failure mode 7 (the same-user forgery ceiling), the lane line, data design, guard row, two claims and two moved-out bullets updated; `fast-lane.test.sh` case "a review record names only the lane's tip" is replaced by "a reviewer session of another commit never lands", and "a hand-typed GO with no reviewer record never lands" is added (the previous design merged it), each with its Break line.
- 2026-10-27, round 2: size line 52 files, 1550 changed lines; C5, C6 and C7 headers re-sized.

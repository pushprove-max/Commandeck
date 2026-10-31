# plugin-open-2026-10-31 -- the open plugin issues in one unit

Owner's words: the owner, 2026-10-31: "then start a unit for all open plugin issues. open a 4th build slot just for it." One unit, no split, whatever the size caps say.
Owner's additions: the two existing-test edits, setup-gate.test.sh:35 and builder-codex-pass-test-edit.test.sh:44 (the owner, 2026-10-31).
Goal: Close the open plugin issues in one unit: new guards and checks, Codex pass retry and failure reasons, steadier shell tests, a pass report, a guard review; Closes what is done, Refs the rest.
Plan: .claude/plans/plugin-open-2026-10-31.md
Tier: Standard; LOCAL merge only; changed-file tests only; no test-timeout raises.
Split override: the owner's order names one unit, no split, whatever the size caps say.
Build order: C1 to C15 in order; C3 before C14; C7 before C8; C15 last.
- Planned size: 83 files, 2150 changed lines
New tests: plugin-open-2026-10-31 76
Version: 0.64.0 (a minor: new behaviour), unless `bash ci/version-check.sh` at merge time says another number is taken.
Closes: #502 #503 #504 #507 #509 #510 #511 #512 #514 #515 #516 #517 #518 #519 #520 #521
Refs: #492 #500 #501 #506 #508 #513
Timed checks: run-shell-tests.test.sh :24-321; dashboard-built-parallel.test.sh :10-60; orca-wait.test.sh :33-235; merge-unit-local.test.sh :14, :200 (`rg 'sleep|timeout|wait_for|SECONDS|date \+%s'`, 2026-10-31). Every new case goes after them, at the end of its file; no heavy fixture is added. New file builder-codex-pass-retry.test.sh holds its one slow case, the session limit, last.

## Merge

- Merge commit message: `Closes` each issue on the Closes: line, then `Refs #492`, `Refs #500`, `Refs #501`, `Refs #506`, `Refs #508`, `Refs #513`.
- An issue whose outcome below reads partial moves from Closes to Refs before the merge: #503 (A1), #506 (A2).
- Main closes these four by hand, each with its comment; both judges confirmed them, 2026-10-31.
- #492 comment: no shipped test carries the own-lane marker, so joining the batch gains 0 s and the issue's keep-if-faster rule keeps nothing. Retest: `rg -n '^# own-lane:' scripts hooks` hits one fixture line.
- #500 comment: `Subject growth:` is not in the plugin; the new-test cap is one number and cites no ruling. Retest: `rg -n 'Subject growth' scripts hooks skills templates config docs` prints nothing.
- #501 comment: the plugin has no cap-lift comment and no approval file; the cap refusals state the rule as it runs. Retest: `rg -n 'approvals/|continue-\$|answered "lift"' scripts/builder-codex-pass.sh` prints nothing.
- #508 comment: the gate this bug names does not exist in the plugin. Retest: #500's command prints nothing.

## Why

The order is every open plugin issue in one unit. Reading each issue against this tree changed what five of them are. The code #500, #501 and #508 describe is not in the plugin, and #492 has nothing to speed up, so all four are proposed for closing. #509 is a bug in a host guard the plugin does not have, so it closes by proof in the #519 guard. #515 is more than the file mode: the specs write `decision.sh` bare, and no seat has the scripts folder on its PATH. #520 asks for the existing read tracker, but the plugin's tracker records no file paths, so this unit adds a small recorder. The host commits named for #507 and #510 are unrelated work and only mention the numbers. #511 is a port of the host's capacity retry. #502's incident cause stays unproved, so the plan names every reason a session can give. #518 reads an untracked file, because a command in a tracked file would run from any cloned repository. Two existing test lines blocked #504 and the new hooks; the owner approved both.

## Prior art

- Host c64bbb31e: #511 (host issue 3327 only). No later host commit touches that script or its test (`git log c64bbb31e..main`, 2026-10-31).
- Host main, read 2026-10-31: `generated-read-guard.sh` (#519), `bugfix-test-lock.sh` (#517), `ruling-cite-gate.sh` (#521), `tier1-stop.sh` (#518's replay and stop order), `companion-read-guard.sh` (#520's edit check).
- Named for a host fix, none found: 578e154cd (a login bug) and 9f68c7976 (a stylesheet) only mention #507 and #510. Both host twins are open.
- No host fix, host issue open: #502, #503, #504, #508, #509, #515. No host twin: #506, #512, #516.
- No plugin counterpart: the host's `.claude/approvals` grant and its worker block (#509's bug); the 400-line Builder rule (read-range-guard.sh has it); `peek.sh` advice; `companion-read-guard`'s hard-coded file list; `ruling-cite-gate --id`; `file_unit_issues_help_exits_clean`; `try_pass`; `Subject growth:` (#500, #508).
- Standard: retry with backoff on a server overload, capped, on one named error (AWS Well-Architected reliability pillar). Library: none; `git check-attr` and the shell are enough.
- Standard: templates/test-rules.md: never weaken a test; each new test names its bug.

## Data design

- `<git dir>/builder-pass-failed` (C5, new): one tab-separated line per pass `<unit> <N> <kind> <tree> <reason> <count>`: a reason may hold spaces. Writer: the pass, just before it dies on a failed reviewer. Reader: the pass, before the launch. Reset: a new tree or round misses the key, a round file written removes the line, main removes the file. Per worktree, outside the tree.
- `$SOCKS/launched-<k>` (C5, new): one stamp per reviewer try, as on the host; `reviewer_session` reads the newest, so a retry never finds the try before it. Removed with `$SOCKS`.
- `<git dir>/commandeck-stop-checks` (C10, new): `<tree> <cksum of the checks file> <rc>` and the kept message beside it. One writer, the Stop hook. Written after each run. Same key replays; a new tree or a changed checks file runs. Outside the tree, so writing it changes no tree id.
- `.claude/stop-checks` (C10, new): read from the main checkout. One command per line, `#` comments, `seconds: <n>` (default 30, cap 120), one deadline for the whole run. Written by hand, never by setup, so setup keeps no copy. Refused when its resolved target is tracked in the checkout that owns that target, so a link or a linked `.claude` folder cannot bring in a clone's file. Absent: the hook does nothing.
- `.claude/bugfix-lock` (C9, new): one repo-relative path per line, `#` comments; absolute, `..` and glob lines ignored with a warning. Written and emptied by the Builder. Run state, never committed: in `IL_STATE`, `.gitignore` and worktree-setup.sh's shared exclude.
- `.claude/companions.tsv` (C8, new): `<edited path><TAB><contract path>[<TAB><why>]`, repo-relative; a trailing `/` on the first is a folder. Written by hand; absent means nothing runs and nothing is recorded. A line with no contract warns on stderr naming its line and pairs nothing, as a bad lock line does.
- `/tmp/claude-read-tracker-<session id>` (C8, new): one absolute path per line. One writer, read-record.sh, only when the pairs file exists. Reader: the guard. A session id must be a UUID. Never cleaned, as the other `/tmp/claude-*` files; a lost file costs one more read.
- `reason` on a fire log row (C3, new): `[a-z0-9-]{1,40}`, block rows only, from `HOOK_FIRE_REASON`; any other shape is dropped. Readers: the summary's `reasons` object. Old rows have none. The dashboard reads rows by key and ignores it.
- `passes` on a unit-ledger row (C12, new): `[{n, kind, verdict, p0, p1, p2, p3}]`, one per round file. On every new row; null and named in `gaps` when any round cannot be read, never 0, as unit-ledger.sh:14 rules. Reader: review-pass-report.sh. Rows from before have no key and read as null.
- `Test edit: <path> test:<label> ruling:<id>` (C4, changed): one line per test. Two tests of one label are `<label> #1`, `<label> #2`. Lives in main's rulings; read by `test_edit_refusals`. `<label>` is the text up to the last ` ruling:`, spaces allowed; `(file)` covers a data file's line only; on a code line it approves nothing.
- The label of a lost line (C4, changed at pass 4, class-miss): test-edit-labels.sh keeps no list. A lost non-blank line of a code file gets its test's label or is refused, helpers, imports and comments included; a line of a data file (`.json`, `.txt`, `.md`, `.yml`, `.yaml`) is `(file)`. A refused line prints `(line)<TAB><line number><TAB><exact text>` and the run exits 2 naming `<path>:<line>`, after every row; any failure of git or of the reader itself exits 3, so it never reads as no edits. `(line)` is a reserved label.
- `Test edit: <path> line:<exact line text> ruling:<id>` (C4, new): one approval unlocks one refused line of that exact text and nothing else. N lost identical lines need N such lines; each is spent once per run. It never covers a labelled or `(file)` line, and `test:(file)` never covers a refused line. The text is the old line whole, spaces kept, up to the last ` ruling:`. The refusal prints this ready-to-paste line, one row per refused line. Stateless: every run reads only git and main's rulings, so a refused edit is retried by restoring the line or by main making the change, whatever ran before. The fixed list is under Protocols.
- A read proof (C8, changed at pass 3, false-read-proof): `shell_reads.py` in `proof` mode prints a path only when the command text alone shows contract text reached the agent. An allowlist: a whole-file printer (`cat`, `nl`, `tac`, `less`, `more`, `bat`, `batcat`) on a non-empty file with no flag that can hide lines, or a head, tail or `sed -n` window that overlaps a non-empty file. A search, jq, diff, awk, cut, sort, uniq and any other tool prove nothing: an empty result cannot be told from the command. A word with a glob, `$` or `~`, a `cd` that is not one plain argument, `pushd`, `popd` and a spaced `2 >` prove nothing: the lexer drops quotes, so the path would be a guess. The non-proof rules above it stand. A lost proof costs one more read. The guard modes (`dump`, `read`, `saved`) do not change.
- `docs/guard-review-2026-10-31.md` (C14, new): written once by the Builder from the summary; nothing reads it.
- No migration, with one exception: every new key and file is optional, and an old file reads as before. The exception is a path-only `Test edit: <path> ruling:<id>` line, which stops approving (issue 504). The refusal prints the ready-to-paste lines carrying the id from main's old line; nothing is approved automatically.

## Decisions already made

- D1 #492, #500, #501, #508: no code. See Not in this unit.
  Test: none, no line changes
- D2 #512, #515: `chmod +x` on the file, so the pass's `git add -A` keeps 100755: `update-index` alone is staged back. Every bare script word in a spec or template becomes a path that runs: chmod alone leaves `command not found`. The spec's two `plan-check.sh` words are the same bug and are fixed with it.
  Test: "the spec's decision.sh command runs"
- D3 #507: `head -1` at orca-wait.sh:333, as main-watch reads it. No shared reader for one line.
  Test: "a quoted Pass line keeps the kind"
- D4 #510: a plain assignment `HOOK_FIRE_REASON=<slug>` before each refusal, `exit 2` or `HOOK_FIRE_BLOCK=1`, the shape of `HOOK_FIRE_BLOCK`. A slug names the rule refused, as `search-first` or `past-clear-line`. Reading the hook's stderr would need a process or a temp file on every call, which the helper's rule bars, and a trap sees only the exit, not the words.
  Test: "a block row keeps its reason"; "a hook that refuses sets a reason"
- D5 #504: approvals name tests. New scripts/test-edit-labels.sh maps each lost line of a code file: a `check` statement and its continuation lines to that label; a line inside an `it(` or `test(` block, which ends at its closing line of equal indent, to that label; any other line, helpers, setup and comments included, stays refused, naming the line, and one approval naming that exact line unlocks that one line and nothing else (the owner). `(file)` stays only for `.json`, `.txt`, `.md`, `.yml` and `.yaml`, and `test:(file)` on a code line approves nothing (the owner, which deletes the list of lines that earned `(file)`). The refusal prints the exact lines main must add. `--edited` stays for the counts. A path-only line approves nothing (the owner, 2026-10-31).
  Test: "a test the line does not name is refused"
- D6 #511: the host's retry, waits 60 and 180 s, in a `BY=codex` branch; a Claude reviewer keeps its plain wait. The ticker's kill moves after the retry loop.
  Test: "capacity_retry_reruns_only_failed_slot"; "other_failure_not_retried"
- D7 #502: the companion exits 1 for any turn not completed and prints no reason, so the reason comes from the session: `error.codex_error_info`, else `error.message` cut to 80 characters, else `aborted: <reason>`, else `no reason in the session`. The refusals at :2141 and :2144 print it, and :2144's `Run the same pass again` goes. A third start with the same unit, round, kind, tree and reason is refused, naming the reason and `ask-main.sh`; it prints no way past. A new tree passes, or main removes the record.
  Test: "the refusal names the stop reason"; "a third same failure is refused"
- D8 #506: default `cores / 2`, then one less when `uptime`'s first load figure is at or over the core count, floor 1; an unreadable load cuts nothing. 3 of 8 is the measured count that passed at load 29. `COMMANDECK_SHELL_TEST_JOBS` still wins. `PYTHONDONTWRITEBYTECODE=1` stops the fence's false alarm. No retry of a hung file: that is a timeout raise by another name.
  Test: "default jobs fall with the load"; "a python import leaves the fence whole"
- D9 #519, #509: the host's rule and lexer, moved to hooks/lib/shell_reads.py, less the items under Prior art. `set` counts as generated as well as `true`: `git check-attr` prints `set` for a bare attribute (A4). `git check-attr` alone decides, so a nested attribute file counts. The word prefilter only picks whether to run the lexer, so a word in an echo refuses nothing. The guard joins the read-only keep-list: a reviewer reads, and that is what #519 bounds.
  Test: "an echo label passes"; "an attribute in any form counts"; "a read-only run keeps the generated guard"
- D10 #503: the guard refuses a shell command with a word under `*/tool-results/*` in a stage that is no echo or printf, and names the Read and Grep tools. A refusal stops before the prompt, needs no permission rule and changes no write rule. No allow rule: its match on a linked path is unproved, and an added directory grants writes.
  Test: "a shell read of saved output is refused"
- D11 #520: new read-record.sh on PostToolUse `Read|Bash`, default tier: read-tracker.sh is strict-tier and records no paths. Shell reads come from shell_reads.py. `# codex: skip` on the guard.
  Test: "a read opens the edit"
- D12 #517: the host's hook, with its text rewritten for this repo; it does not parse Bash, a tripwire as the issue says.
  Test: "a listed test is refused"
- D13 #518: a new file, not `typecheckCommand` or a new config key: reusing a key would start blocking turns in projects that never asked, and setup rebuilds that file. Main's checkout is skipped: the issue is about edits between review passes. All refusals are exit 2, each saying failed, deadline or could not run. Each line runs under `bash -c` in the worktree whose Stop fired, with the hook's environment; the file is read from main's checkout. `seconds:` is one deadline shared by every command: a Stop hook has no `onFailure`, so a run must end inside the entry's own timeout. A failed command leaves the rest to run; the deadline ends them.
  Test: "a tracked checks file runs nothing"; "a link to a tracked file runs nothing"; "a changed checks file runs again"; "a deadline says the deadline fired"; "two commands share one deadline"
- D14 #521: the host's gate, claims rewritten as `owner ruling`, `owner's ruling`, `owner ruled` or `ruling:r-<id>`. Paths `*/projects/*/memory/*` and `.claude/rules/`: a profile's memory path holds no `.claude`. hooks/lib/ruling-id.sh holds the id check; `ruling_id_ok` calls it and keeps its unit clause. Only added lines are read.
  Test: "an unlogged id is refused"; "a profile memory path is screened"
- D15 #514: the merge adds `passes`; a new report reads the ledger. A pass found something when its round has a P0, P1 or P2 line. Kind of unit: the plan's `Tier:` word, `unknown` when absent. A row with no pass data shows verdicts only and says so.
  Test: "a later pass that found a P2 counts"; "an unread round leaves passes null"
- D16 #516: a section in rules-details.md and a runnable example, templates/drift-guard-example.sh, so the template is itself tested.
  Test: "the example fails on two copies that differ"
- D17 #513: a document only: verdicts and proposed retire-when lines. No hook header changes, no guard moves.
  Test: none, a document; the summary fix under it is tested

## Assumptions

- A1 [uncertain] A PreToolUse exit 2 comes before Claude Code's permission prompt, so #503's prompt never opens. Builder check after C7, in a live seat: run the issue's `sed | rg | cut | head` on a saved output. Refusal, no prompt: Closes #503. A prompt: keep the refusal, `#503: partial -- the prompt still opens`, move to Refs.
- A2 [uncertain] C6 is enough for #506. Builder check after C6, on the Mac: three full runs at the default job count with load1 at or over the core count. All green: Closes #506. Any red: `#506: partial -- <test>`, move to Refs. No timeout moves either way.
- A3 [settled] The Read tool reads a saved tool output: this seat read one with `limit: 2`, no prompt, 2026-10-31.
- A4 [settled] `git check-attr linguist-generated` on `a linguist-generated=true`, `b linguist-generated`, `c -linguist-generated`, `d`: `true`, `set`, `unset`, `unspecified` (2026-10-31).
- A5 [settled] Codex plugin 1.0.6: a turn not `completed` exits non-zero and the `--json` payload carries no error text (`rg` of its lib/codex.mjs, 2026-10-31).
- A6 [settled] `command -v decision.sh plan-check.sh` prints nothing in a worker seat, 2026-10-31.
- A7 [settled] No shipped test carries `# own-lane:`: `rg '^# own-lane:'` hits only a fixture line, 2026-10-31.

## Protocols

- Fire log reason: Hook sets, helper checks shape, row carries, summary counts. A subshell's assignment is lost, as for `HOOK_FIRE_BLOCK`: set it in the hook's own shell.
- New hook rules, one place: file mode 100755, `#!/usr/bin/env bash`, the fire-log arm line at top level before any decision, a backticked command in each `BLOCKED:` text; a PreToolUse entry that can refuse takes `onFailure: block` and timeout 30 or more; a Stop entry takes no `onFailure`.
- Shell reads: `shell_reads.py <cmd> <cwd>` prints `dump<TAB><path>`, `read<TAB><path>` or `saved<TAB><path>`, one per line. Consumers: generated-read-guard.sh (`dump`, `saved`), read-record.sh (`dump`, `read`).
- Label reader's rule:
  - Label: a line of a `check "<label>"` in a `.sh` file that starts its line, with its backslash continuations; or an `it(` or `test(` in a JS or TS file that starts its line, has a string label and has a closing line of equal indent or fits on one line. A label with `$`, a backtick, a backslash or a tab, equal to `(file)` or `(line)`, or ending ` #<digits>` gives no label. A test whose lines hold a second `check`, `it(` or `test(`, on its first line, a continuation or nested in its block, gives no label, so one approval never covers two tests.
  - Data file, `.json`, `.txt`, `.md`, `.yml`, `.yaml`: `(file)`.
  - Every other lost line: refused. The reader tells no comment, helper, setup line or file kind apart.

## Steps

- modify scripts/decision.sh -- C1, mode only
- modify scripts/seat.sh ~4 -- C1
- modify scripts/orca-wait.sh ~2 -- C2
- modify hooks/lib/hook-fire-log.sh ~10 -- C3
- modify scripts/hook-fire-log-summary.sh ~20 -- C3
- modify hooks/*.sh ~105 -- C3 the 25 hooks that refuse; C1, C7, C11 lines
- new scripts/test-edit-labels.sh ~45 -- C4
- modify scripts/builder-codex-pass.sh ~105 -- C4,C5,C11
- modify scripts/run-shell-tests.sh ~12 -- C6
- modify scripts/__tests__/fixtures/dashboard-built-setup.sh ~3 -- C6
- modify hooks/hooks.json ~24 -- C7-C11
- new hooks/lib/shell_reads.py ~85 -- C7
- new hooks/generated-read-guard.sh ~60 -- C7
- new hooks/{companion-read-guard,read-record}.sh ~85 -- C8
- new hooks/bugfix-test-lock.sh ~60 -- C9
- new hooks/stop-checks.sh ~85 -- C10
- new hooks/ruling-cite-gate.sh ~75 -- C11
- new hooks/lib/ruling-id.sh ~15 -- C11
- modify scripts/{merge-unit-local,unit-ledger,install-lib,worktree-setup}.sh ~16 -- C9,C10,C12
- modify .gitignore ~2 -- C9,C10
- new scripts/review-pass-report.sh ~65 -- C12
- new templates/drift-guard-example.sh ~20 -- C13
- modify templates/{test-rules,main-rulings,_builder-brief-template,rules-details,AGENT_STARTUP,main-session}.md ~40 -- C1,C4,C5,C7,C9,C13
- new docs/guard-review-2026-10-31.md ~120 -- C14
- modify docs/{hooks,configuration,tests,review-loop}.md ~30 -- C15
- modify .claude-plugin/plugin.json ~1 -- C15
- modify README.md ~1 -- C15 badge
- modify CHANGELOG.md ~30 -- C15
- modify scripts/__tests__/{orca-wait,decision,builder-codex-pass-test-edit,run-shell-tests,dashboard-built-parallel,merge-unit-local}.test.sh ~105 -- tests
- modify hooks/__tests__/{setup-gate,codex-dispatch}.test.sh ~12 -- C7, approved count
- new scripts/__tests__/{hook-fire-log-summary,builder-codex-pass-retry,review-pass-report,drift-guard-template,test-edit-labels}.test.sh ~370 -- tests
- new hooks/__tests__/{generated-read-guard,companion-read-guard,bugfix-test-lock,stop-checks,ruling-cite-gate}.test.sh ~420 -- tests

## Cuts

- C1 #512, #515, ~20. `chmod +x scripts/decision.sh`, checked with `git ls-files -s` after a `git add -A`. seat.sh:495, :497, :499, :508: `bash $PP_SCRIPTS_Q/<script>`. main-session.md:23, :24, :149: `bash scripts/decision.sh`, the plugin-relative form that file uses at :131. ask-stop-records-decision.sh:76 as its :75. Tests: decision.test.sh.
  Produces: spec text. Consumes: `PP_SCRIPTS_Q`. Consumers: every plan author, judge and main; no test pins the old words.
- C2 #507, ~10. D3. Tests: orca-wait.test.sh, at its end.
  Produces: none. Consumes: the round file. Consumers: the wake text only.
- C3 #510, and the `registered` bug #513 needs, ~250. D4. In `_hook_fire_log_write`'s block arm: keep `HOOK_FIRE_REASON` when it fits the shape; arm clears it. Summary: `reasons {slug: n}` per hook; the registry reads the word after run-hook.sh, or the first word without it: today every hook reads unregistered but run-hook.sh. Sites: every `exit 2` and every `HOOK_FIRE_BLOCK=1`, seven of those in five hooks, four of which have no `exit 2`. Mechanical, by a Sonnet helper, one slug per kind of refusal, no text changes. Tests: new hook-fire-log-summary.test.sh.
  Produces: `reason`, `reasons`. Consumes: none. Consumers: dashboard.sh:762-768 reads rows by key; hook-fire-log-coverage.guard.test.sh unchanged.
- C4 #504, ~150. D5. `test_edit_refusals` reads the script's labels and the `test:` lines; the refusal keeps its head so the pinned greps stand, then lists the lines to add. test-rules.md:13, main-rulings.md:16, _builder-brief-template.md:123 state the new shape. Tests: new test-edit-labels.test.sh; builder-codex-pass-test-edit.test.sh, new cases at the end, and :44, approved, to `Test edit: t/x.test.sh test:two ruling:$OKID`.
  Produces: test-edit-labels.sh, the line shape. Consumes: main's rulings. Consumers: :729's callers at the launch (:1551) and `--verify` (:864); new-test-count.sh is unchanged.
- C5 #511, #502, ~230. Host parts in order: `pass_waits` sets `RETRY_WAITS` ("0 0" when the test-waits file exists); `launch_reviewers <k...>` from :2072-2079, :2095-2103, :2115-2117; `launched-<k>`; `reviewer_overloaded <k>`; the loop, with a `stamp` line. `pass_threads` keeps reading to the end event and leaves out a session that ended overloaded with no reply. Then `reviewer_stop_reason <k>`, the two refusals at :2141 and :2144, and `builder-pass-failed`, with main's reset in main-session.md and docs/review-loop.md. Catches: a lost pass on one overload; a retry of a real failure; a blind third start. Tests: new builder-codex-pass-retry.test.sh with its own stub written over the fixture's, so the shared fixture is not edited; waits file 5 for the late record.
  Produces: `builder-pass-failed`. Consumes: session files. Consumers: `earlier_passes`, `--verify` (off-record tries never reach them).
- C6 #506, ~80. D8; the runner prints its job count; tests stub `getconf` and `uptime`, which both hosts have. The ps stub in dashboard-built-setup.sh, as dashboard-tests-panel.test.sh:11-13. `COMMANDECK_SHELL_TEST_SECONDS` exported near the top of run-shell-tests.test.sh, an added line: :239 overwrites the real list today, which leaves slowest-first with one row. Then A2.
  Produces: job line. Consumes: `getconf`, `uptime` under `LC_ALL=C`. Consumers: `.githooks/pre-push:16`, CI: neither sets jobs.
- C7 #519, #509, #503, ~290. Python from the host's guard into shell_reads.py, Protocols' output added. PreToolUse `Read|Bash`, `onFailure: block`, timeout 30. A Read runs `git check-attr` on its file; a Bash call runs the lexer only on the word prefilter or `tool-results`, then `git check-attr` on each path. `generated-read-guard.sh` joins `READ_ONLY_KEEP` at codex-dispatch.sh:182. One AGENT_STARTUP.md line steers seats to the Read tool. A lexer failure reads as no paths: the hook is `onFailure: block`, and a crash must not stop every Bash call. Tests go through run-hook.sh for GNU `realpath`. Catches: a whole read by any tool, in any seat, reviewers included. Then A1.
  Produces: the guard, shell_reads.py. Consumes: `git check-attr`. Consumers: read-record.sh (C8); `read_only_run` in codex-dispatch.sh; read-range-guard.sh is independent.
- C8 #520, ~190. D11. Refusal names the contract and the why. Catches: an edit written before its contract was read. Tests: new companion-read-guard.test.sh.
  Produces: tracker file. Consumes: shell_reads.py, session id. Consumers: the guard only.
- C9 #517, ~115. test-rules.md gains the flow under Never weaken. `.claude/bugfix-lock` joins `IL_STATE` (install-lib.sh:53), `.gitignore` and the list at worktree-setup.sh:62, which reaches a project that has not rerun setup. Catches: a failing test reshaped to agree with its bug; the lock committed by the pass's `git add -A`. Tests: new bugfix-test-lock.test.sh.
  Produces: the lock. Consumes: none. Consumers: Builders; test-rules.test.sh reads the file whole; doctor.sh:105 and setup.sh:581 read `IL_STATE`; leak-test.test.sh:142 needs the `.gitignore` line.
- C10 #518, ~205. Order: `stop_hook_active`, main's checkout, the file, tracked check on its `realpath` through `git -C <target's folder> ls-files`, key from a temp index without `.claude/briefs` and the file's cksum, replay, then one deadline: each command gets `timeout -k 2 <seconds left>`, and at the deadline the rest do not run and the text names them. 120 + 2 s fits the entry's timeout of 135, no `onFailure`. `.claude/stop-checks` joins `IL_STATE` and `.gitignore`: tracked, it is refused, so an ignore rule keeps it working and doctor.sh reports a tracked one. Catches: a loop; a clone's command; a stale green; a check that never ran reading as a pass; a run outliving its Stop entry.
  Produces: `.claude/stop-checks`. Consumes: main's path (`pp_project`). Consumers: docs/configuration.md.
- C11 #521, ~170. D14. Catches: an invented ruling obeyed as the owner's. Comments: ruling-log.sh:8 names the real hook; dependency-addition-guard.sh:17 and codex-dispatch.sh:36-37 drop the unshipped names; edit-content-tripwires.sh:17 names the real one.
  Produces: the gate, ruling-id.sh. Consumes: the ruling log. Consumers: `ruling_id_ok` (:716-724).
- C12 #514, ~170. D15. The merge's `REVIEW` jq gains `passes`, counted with the line shape at :1283; unit-ledger.sh adds the key beside `passKinds`, so `gaps` names a null.
  Produces: `passes`, the report. Consumes: round files, the ledger. Consumers: dashboard ledger readers ignore a new key.
- C13 #516, ~90. D16. rules-details.md beside its drift line; docs/tests.md shows the worked example.
  Produces: a template. Consumes: none. Consumers: `il_own` copies only named templates, so setup is unchanged.
- C14 #513, ~120. On the Mac, after C3: `hook-fire-log-summary.sh 8`; a row for each hook that never fired, fired with no block or advice, or blocks most: verdict `keep`, `narrow` or `retire`, reason, a proposed retire-when line. Read each quiet hook first.
  Produces: the document. Consumes: the summary. Consumers: none.
- C15 version and docs, ~60. plugin.json, README badge, the CHANGELOG entry in the user-facing style, docs rows for every new hook and file.
  Produces: 0.64.0. Consumes: all. Consumers: `ci/version-check.sh`.

## Breaks

Break: scripts/__tests__/builder-codex-pass-test-edit.test.sh -- a test the line does not name is refused -- scripts/builder-codex-pass.sh test_edit_refusals label match
Break: scripts/__tests__/builder-codex-pass-retry.test.sh -- other_failure_not_retried -- scripts/builder-codex-pass.sh reviewer_overloaded
Break: scripts/__tests__/builder-codex-pass-retry.test.sh -- a third same failure is refused -- scripts/builder-codex-pass.sh failure gate
Break: scripts/__tests__/hook-fire-log-summary.test.sh -- a bad reason is dropped -- hooks/lib/hook-fire-log.sh shape check
Break: hooks/__tests__/generated-read-guard.test.sh -- a whole Read is refused -- hooks/generated-read-guard.sh generated rule
Break: hooks/__tests__/codex-dispatch.test.sh -- a read-only run keeps the generated guard -- hooks/codex-dispatch.sh READ_ONLY_KEEP
Break: hooks/__tests__/generated-read-guard.test.sh -- a shell read of saved output is refused -- hooks/generated-read-guard.sh saved rule
Break: hooks/__tests__/companion-read-guard.test.sh -- an unread contract refuses the edit -- hooks/companion-read-guard.sh tracker read
Break: hooks/__tests__/companion-read-guard.test.sh -- an errored Read counts for nothing -- hooks/read-record.sh error check
Break: hooks/__tests__/bugfix-test-lock.test.sh -- a listed test is refused -- hooks/bugfix-test-lock.sh lock match
Break: hooks/__tests__/stop-checks.test.sh -- a tracked checks file runs nothing -- hooks/stop-checks.sh tracked check
Break: hooks/__tests__/stop-checks.test.sh -- a link to a tracked file runs nothing -- hooks/stop-checks.sh realpath step
Break: hooks/__tests__/stop-checks.test.sh -- one tree runs once -- hooks/stop-checks.sh state write
Break: hooks/__tests__/ruling-cite-gate.test.sh -- an unlogged id is refused -- hooks/lib/ruling-id.sh log read
Break: scripts/__tests__/merge-unit-local.test.sh -- the ledger keeps each pass -- scripts/unit-ledger.sh passes key

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| Quoted path with a space | `sed -n 1,5p "<folder with a space>/tool-results/x.txt" \| rg a \| head -3` | refused, the lexer keeps the quoted word whole | a shell read of saved output is refused |
| Late overload record | the companion exits 1; the session's error lands two seconds after | retried, only that reviewer | capacity_retry_reruns_only_failed_slot |
| Two checks outlive one budget | `seconds: 120`, two `sleep 70` (in the test `seconds: 2`, two `sleep 1.5`) | the second is cut at the shared deadline, turn held, the text says the deadline fired | two commands share one deadline |
| Checks file from a clone | `.claude/stop-checks` tracked in git | nothing runs, one line says why | a tracked checks file runs nothing |
| Same failure, third start | two failed passes on one tree and reason | refused, names the reason and tells the Builder to ask main | a third same failure is refused |
| A numeric sed address with automatic printing on | `sed 1,5p gen.json`, `sed '1,5p' gen.json` | refused: `sed` is a window only as `sed -n a,bp` or `sed Nq` | a sed with no range is refused |
| A window that covers the file | `head -10000 gen.json`, `sed -n 1,99999p gen.json`, `tail -n 5000 gen.json` on 300 lines | refused, as a Read whose limit covers the file | a limit over the file is refused |
| A tool or pattern that prints every line | `sort gen.json`, `cut -c1-80 gen.json`, `rg . gen.json`, `grep -v zzz gen.json` | refused | a cat is refused |
| A shell read that may not have run or was not seen | `false && cat c`, `if false; then cat c; fi`, `cat c > /dev/null`, `cat c \| wc -l`, `x=$(cat c)`, `wc -l c` | no proof recorded, the edit stays refused; the generated guard still reads the branch | an errored Read counts for nothing |
| A MultiEdit with a path on each edit | `edits: [{file_path: <listed path>}]` | companion guard and ruling gate screen every edited path, each with its own edits | an unread contract refuses the edit; a claim with no id is refused |
| A shell read of a path the reader must guess | `cat 'src/*.ts'`, `cat '~/x'`, `cd; cat c`, `pushd lib; cat c`, `cat c 2 > out` | no proof recorded, the edit stays refused | an errored Read counts for nothing |
| A cut Stop state line | `<tree> <cksum>` with no rc | the line is no key: the checks run again, never read as green | a changed checks file runs again |
| A shell query that shows no contract line | `grep -n no-such-text c`, `sed -n 900,910p c` on a shorter file, `jq keys c`, `grep -v . c`, `head -n 0 c` | no proof recorded, the edit stays refused | an errored Read counts for nothing |
| A lost test line in a shape the label reader does not know | `check 'x' 1 1`, `check"x" 1 1`, `fresh; check "x" 1 1`, `it.only("x", ...)` | test-edit-labels.sh exits 2 naming `<path>:<line>`, never `(file)` | an unknown test shape is refused by line |
| A lost line inside a test the reader cannot name | body of `test.each(...)("x", ...)`, `it(name, ...)`, an `it("x", ...)` with no closing line, a `def test_` body, the second line of a check whose quote stays open | exit 2 naming the line, never `(file)` | an unknown test shape is refused by line |
| A label that names no one test | `check "(file)" 1 1`, `check "x #1" 1 1`, `check "$v" 1 1` | exit 2 naming the line, so no label can pose as `(file)` or a numbered test | an unknown test shape is refused by line |
| A lost code line that is no labelled test | `run_case "x"`, `registerCase("x");`, `const c = registerCase("x");`, a line in a helper body, `import "./shared-tests";`, `FAIL=$((FAIL+1))`, `# a comment`, a `# ` line in a here-document, any line of a `.py` test or of a `.test.sh` with no `check`, in a file that sources or not | exit 2 naming the line, one ready `line:` row each, never `(file)` | an unknown test shape is refused by line |
| Two tests under one label | `check "a" 1 1; check "b" 2 2`, `it("a", f); it("b", g);`, `check "a" 1 1 \` then `check "b" 2 2`, `it("inner", ...)` inside `it("outer", ...)` | exit 2 naming the line, so no label covers both | an unknown test shape is refused by line |
| A data file | a lost line of a `.json` fixture | `(file)`, and `test:(file)` approves it | a data line maps to (file) |
| `test:(file)` on a code file | `test:(file)` with a logged id, a lost helper line | approves nothing, the refusal prints the `line:` row | a helper edit needs its line |
| The reader fails | git fails, or its own diff reader fails | exit 3, the gate says `cannot tell`, never no edits | an unknown test shape is refused by line |
| A refused edit retried | the same edit run twice, the index and the approval removed between the runs | refused both times; the exact-line approval or restoring the line ends the refusal, with no state to clear | a line approval unlocks one line |
| One approval, two identical refused lines | both lost, one `line:` approval | the first unlocked, the second refused and printed; two approval lines pass | a line approval unlocks one line |
| A line approval on any other line | `line:` of a labelled or `(file)` line, another path, a different text, a bad id; `test:(file)` on a refused line | approves nothing | a line approval unlocks one line |
| Two tests of one label | `check "same"` twice | `same #1`, `same #2`, so one approval names one test | two tests of one name differ |
| A path-only line from before issue 504 | `Test edit: <path> ruling:<id>` with a logged id | approves nothing; the refusal prints each line with that id | a path-only line gets ready lines |

## Accepted failure modes

- F1 #519, #503, #520: both guards read the command text; a path in a variable or a script passes. A tripwire, as the issues say.
  Test: none, the issue scopes it as a tripwire
- F2 #520: a contract read through a code server or a script does not count; the agent reads it once more.
  Test: none, the refusal names the file to read
- F3 #518: the second Stop on a red tree passes, so a turn cannot loop.
  Test: "stop_hook_active runs nothing"
- F4 #502: a Builder can change the tree or remove the record itself. The refusal is a stop to think, not a lock.
  Test: "main's reset lets it run"
- F5 #514: a P2 line counts as found whether or not main later cleared it.
  Test: none, the ledger holds no cleared count

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- #502's incident cause is unproved: of 3090 October sessions read with `jq` on 2026-10-31, 6 ended overloaded, 5 on a 401, 4 with no reason; none ran 3 to 4 minutes.
- #513 reads 8 days of day files, earliest row 2026-10-21 (`hook-fire-log-summary.sh 8`, 2026-10-31).
- #506: the 3-job point is one run at load 29 on 8 cores (the issue's evidence, 2026-10-31).

## Not in this unit

- #492: no shipped test has the marker (A7) and the merge has no second call, so joining the batch gains 0 s. Nothing is left to port; close.
- #500, #508: `Subject growth:` is not in the plugin; the cap is one number. Close.
- #501: no cap-lift comment here, and the refusal at the cap is accurate. A ruling id would also fail the leak test. Close.
- #513's verdicts: each needs the owner's yes, then a unit.
- A retry of a hung test, or a split of merge-unit-local.test.sh: A2 decides.
- dependency-addition-guard.test.sh:13-15's comment: an existing test.

## Acceptance test

- test file path: decision.test.sh (decision.sh is tracked executable; the spec's decision.sh command runs)
- test file path: orca-wait.test.sh (a quoted Pass line keeps the kind)
- test file path: hook-fire-log-summary.test.sh (a block row keeps its reason; a bad reason is dropped; a hook that refuses sets a reason; the summary counts reasons; a hook behind run-hook.sh reads registered)
- test file path: test-edit-labels.test.sh (a check line maps to its label; a data line maps to (file); an unknown test shape is refused by line; two tests of one name differ)
- test file path: builder-codex-pass-test-edit.test.sh (a test the line does not name is refused; a named test passes; a helper edit needs its line; a path-only line gets ready lines; a line approval unlocks one line)
- test file path: builder-codex-pass-retry.test.sh (capacity_retry_reruns_only_failed_slot; capacity_retry_gives_up_after_last_try; other_failure_not_retried; mixed_failure_not_retried; the refusal names the stop reason; a third same failure is refused; a new tree runs again after a failure; main's reset lets it run; retry_with_no_session_stops_at_limit)
- test file path: run-shell-tests.test.sh (default jobs fall with the load; a python import leaves the fence whole; a test box never writes the real list)
- test file path: dashboard-built-parallel.test.sh (another runner leaves the collect alone)
- test file path: generated-read-guard.test.sh (a whole Read is refused; a limit over the file is refused; a cat is refused; a sed with no range is refused; a bounded read passes; an attribute in any form counts; an unmarked file passes; an echo label passes; a shell read of saved output is refused; an echo naming saved output passes)
- test file path: codex-dispatch.test.sh (a read-only run keeps the generated guard)
- test file path: companion-read-guard.test.sh (no pairs, no refusal; an unread contract refuses the edit; a read opens the edit; an errored Read counts for nothing; another session's read counts for nothing)
- test file path: bugfix-test-lock.test.sh (a listed test is refused; a MultiEdit is refused; an unlisted file passes; a glob line matches nothing; the lock stays out of a commit)
- test file path: stop-checks.test.sh (no checks file, nothing runs; a tracked checks file runs nothing; a link to a tracked file runs nothing; stop_hook_active runs nothing; a failure says failed; a deadline says the deadline fired; two commands share one deadline; a missing command says could not run; one tree runs once; a new tree runs again; a changed checks file runs again; main's checkout runs nothing)
- test file path: ruling-cite-gate.test.sh (a claim with no id is refused; an unlogged id is refused; a logged id passes; a void id is refused; an old line passes; a profile memory path is screened)
- test file path: review-pass-report.test.sh (a later pass that found a P2 counts; rows split by tier; an old row shows verdicts only)
- test file path: merge-unit-local.test.sh (the ledger keeps each pass; an unread round leaves passes null)
- test file path: drift-guard-template.test.sh (the example fails on two copies that differ; the rules carry the section)

## Claims to falsify

- `Subject growth:` appears nowhere in the plugin's scripts, hooks, skills, templates or docs.
- No test but setup-gate.test.sh:35 pins the number of registered hooks.
- Only the two named test lines need an edit; every other test change is an added line.
- No bare `decision.sh` or `plan-check.sh` command survives in a spec or template after C1.
- A PreToolUse exit 2 comes before the permission prompt (A1).
- The ps stub changes no assertion in the 14 files that source the fixture.
- `PYTHONDONTWRITEBYTECODE` removes every false `tree changed` line in a fresh worktree.
- A null `passes` named in `gaps` changes no pinned ledger row.
- An overloaded try never counts toward the pass cap.
- A hook that sets `HOOK_FIRE_REASON` behaves the same with the helper absent.
- `.claude/bugfix-lock` stays out of `git add -A` in a set-up project and in a Builder worktree.
- No Stop run outlives the entry's 135 s, however many commands the file lists.
- A tracked file cannot run as `.claude/stop-checks` through a link, a linked `.claude` folder or a linked worktree.

## Issue cases

- #502 Body 1 -- scripts/builder-codex-pass.sh -- a third same failure is refused
- #503 Body 1 -- hooks/generated-read-guard.sh -- a shell read of saved output is refused
- #504 Body 1 -- scripts/builder-codex-pass.sh -- a test the line does not name is refused
- #506 Body 1 -- scripts/__tests__/fixtures/dashboard-built-setup.sh -- another runner leaves the collect alone
- #506 Body 2 -- scripts/run-shell-tests.sh -- default jobs fall with the load
- #506 Body 3 -- scripts/run-shell-tests.sh -- a python import leaves the fence whole
- #506 Body 4 -- scripts/run-shell-tests.sh -- default jobs fall with the load
- #506 Body 5 -- scripts/__tests__/fixtures/dashboard-built-setup.sh -- another runner leaves the collect alone
- #506 Body 6 -- scripts/run-shell-tests.sh -- default jobs fall with the load
- #507 Body 1 -- scripts/orca-wait.sh -- a quoted Pass line keeps the kind
- #509 Body 1 -- hooks/generated-read-guard.sh -- an echo label passes
- #510 Body 1 -- hooks/lib/hook-fire-log.sh -- a block row keeps its reason
- #511 Body 1 -- scripts/builder-codex-pass.sh -- capacity_retry_reruns_only_failed_slot
- #512 Body 1 -- scripts/decision.sh -- decision.sh is tracked executable
- #514 Body 1 -- scripts/review-pass-report.sh -- a later pass that found a P2 counts
- #515 Body 1 -- scripts/seat.sh -- the spec's decision.sh command runs
- #516 Body 1 -- templates/drift-guard-example.sh -- the example fails on two copies that differ
- #517 Body 1 -- hooks/bugfix-test-lock.sh -- a listed test is refused
- #518 Body 1 -- hooks/stop-checks.sh -- a deadline says the deadline fired
- #519 Body 1 -- hooks/generated-read-guard.sh -- a whole Read is refused
- #520 Body 1 -- hooks/companion-read-guard.sh -- an unread contract refuses the edit
- #521 Body 1 -- hooks/ruling-cite-gate.sh -- an unlogged id is refused

## Done

- #502 Done: a Builder starts a pass that failed twice on one tree -- the pass names why Codex stopped and refuses the third start
- #503 Done: a seat opens its saved tool output with a shell command -- it is told to use the Read tool and no prompt waits for a person
- #504 Done: main approves one test and the Builder edits another in that file -- the pass refuses and prints the line needed
- #506 Done: a user pushes while the machine is busy -- the tests run at fewer jobs and another run's noise refuses no push
- #507 Done: a user reads a wake for a report that quotes a Pass line -- the state line shows the real kind
- #509 Done: a seat runs an echo naming a generated file -- the command runs, nothing refused
- #510 Done: a user reads the hook summary after a day of refusals -- blocks are counted by reason
- #511 Done: a pass meets a Codex capacity error on one reviewer -- that reviewer alone runs again and the pass ends with a verdict
- #512 Done: a user runs scripts/decision.sh by its path -- it runs with no permission error
- #514 Done: a user runs the pass report -- a table shows how often each later pass found a real problem
- #515 Done: a plan author runs the rulings command as the spec writes it -- the command runs and lists matching picks
- #516 Done: a project copies the drift guard and two copies of a fact differ -- the guard fails, naming both files
- #517 Done: a Builder tries to edit a locked failing test -- the edit is refused and the message says to fix the code
- #518 Done: an edit breaks a check the project lists -- the turn is held and says failed, deadline or could not run
- #519 Done: an agent asks for a whole generated file -- the read is refused and the message names a bounded read
- #520 Done: an agent edits a listed path with its contract unread -- the edit is refused, naming the file to read
- #521 Done: an agent cites a ruling that was never made in a memory line -- the edit is refused, saying the id is not logged

## Progress notes

- One line per issue in the evidence file: `#N: built` or `#N: partial -- <what is left>`.
- #492, #500, #501, #508: not built, proposed for closing.
- #513: partial -- the owner's verdicts and the retire-when lines in the hook headers.
- A1 (#503): passed headless, Closes #503.
- A2 (#506): one full Mac run at 3 default jobs, load1 8 to 82, 12 reds, so #506: partial -- builder-codex-pass-closing, builder-codex-pass-threshold, dashboard-live, main-watch-nudge, merge-queue-glob, merge-queue-listing, merge-queue-train, merge-queue, merge-unit-local-cleanup, merge-unit-local, seat-launch, seat-plan-finish. Moved to Refs. Runs 2 and 3 were not started: any red decides, and each run takes 48 minutes.

## Verification

- Each Acceptance test green; `bash scripts/run-shell-tests.sh --changed main` green during the build; the full shell tests green before any push.
- `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- A1 and A2 run and their outcomes written in Progress notes.
- `plan-check.sh` passes this plan; every Break line has its red run.
- Review passes until the unit converges; the closing pass ends `VERDICT: GO` naming no finding.

## Routing

- Builder: this pane's model. Helpers: Sonnet `general-purpose` for reading code, test triage and mechanical edits; Haiku `Explore` for search. Name the model on every call; the Builder brief carries this line.
- Tests run on the PC; A1, A2 and C14 run on the Mac. Red runs only for the Break lines.
- Main adds for each of the two approved edits a path-only `Test edit:` line, for the installed gate, and an approval for this unit's: `test:every registered hook was run` for setup-gate.test.sh:35; a `line:` approval of the old text for builder-codex-pass-test-edit.test.sh:44, a code line that is no check, so `test:(file)` no longer covers it. Main owns both lines.

## Question for the owner

- Answered 2026-10-31: yes to both existing-test edits: setup-gate.test.sh:35, count 50 to 56; builder-codex-pass-test-edit.test.sh:44, the approval names its test. No question is open. #500, #501 and #508 are bugs, each with the retest named under Merge, so none is a close without a retest.

## Facts

- Bare spec and template words; scripts folder variable; pass staging -- scripts/seat.sh:495, scripts/seat.sh:497, scripts/seat.sh:499, scripts/seat.sh:508, templates/main-session.md:23-24, templates/main-session.md:149, scripts/paths.sh:79, scripts/builder-codex-pass.sh:1541 (observed: 2026-10-31)
- Wait reads the last Pass line, the watcher the first -- scripts/orca-wait.sh:333, scripts/main-watch.sh:924 (observed: 2026-10-31)
- Fire log stores shaped fields, block rows carry summary; registry takes the first word -- hooks/lib/hook-fire-log.sh:282-300, scripts/hook-fire-log-summary.sh:48-54, hooks/hooks.json:1-12 (observed: 2026-10-31)
- Gate matches the path only; `--edited` output; callers -- scripts/builder-codex-pass.sh:729-741, scripts/new-test-count.sh:14-34, scripts/builder-codex-pass.sh:864, scripts/builder-codex-pass.sh:1551 (observed: 2026-10-31)
- A path-only line is pinned as approving -- scripts/__tests__/builder-codex-pass-test-edit.test.sh:44-45 (observed: 2026-10-31)
- Launch, session limit, ticker, wait, refusals; thread reader; waits; stamp -- scripts/builder-codex-pass.sh:2067-2079, scripts/builder-codex-pass.sh:2085-2116, scripts/builder-codex-pass.sh:2141-2144, scripts/builder-codex-pass.sh:566-628, scripts/builder-codex-pass.sh:105, scripts/builder-codex-pass.sh:81 (observed: 2026-10-31)
- The stub has no failure modes -- scripts/__tests__/fixtures/builder-codex-pass-setup.sh:29-54 (observed: 2026-10-31)
- Jobs, timeout, fence; pre-push sets no jobs -- scripts/run-shell-tests.sh:51-54, scripts/run-shell-tests.sh:124-127, .githooks/pre-push:16 (observed: 2026-10-31)
- Tests panel reads every process; a stub exists -- scripts/dashboard.sh:1019-1031, scripts/__tests__/dashboard-tests-panel.test.sh:11-13 (observed: 2026-10-31)
- Count pin; the registered list -- hooks/__tests__/setup-gate.test.sh:35, hooks/__tests__/setup-gate.test.sh:28-34 (observed: 2026-10-31)
- Tracker is strict-tier, no path record -- hooks/read-tracker.sh:7, hooks/hooks.json:81 (observed: 2026-10-31)
- Read-only keep-list; a run off it skips the hook -- hooks/codex-dispatch.sh:182, hooks/codex-dispatch.sh:279 (observed: 2026-10-31)
- Refusals with exit 0 -- hooks/context-clear-stop.sh:71-74, hooks/cos-unfinished-stop.sh:34, hooks/cos-inbox-waiter-stop.sh:68, hooks/claude-worker-notify.sh:63, hooks/opus-orchestrator-autonomy.sh:137, hooks/lib/hook-fire-log.sh:99 (observed: 2026-10-31)
- Run state list and its readers; shared exclude; ignore rules; a Stop entry has no `onFailure` -- scripts/install-lib.sh:53, scripts/doctor.sh:105, scripts/setup.sh:581, scripts/worktree-setup.sh:62, .gitignore:1-11, scripts/__tests__/leak-test.test.sh:142, hooks/__tests__/hook-on-failure.guard.test.sh:6 (observed: 2026-10-31)
- Named comments -- hooks/ruling-log.sh:8, hooks/dependency-addition-guard.sh:17, hooks/codex-dispatch.sh:36-37, hooks/edit-content-tripwires.sh:17 (observed: 2026-10-31)
- Ruling log path; id check -- hooks/ruling-log.sh:17-18, scripts/builder-codex-pass.sh:716-724 (observed: 2026-10-31)
- Ledger review block; null and named rule -- scripts/merge-unit-local.sh:778-791, scripts/unit-ledger.sh:14, scripts/unit-ledger.sh:88-89 (observed: 2026-10-31)
- Finding line shape; cap refusals -- scripts/builder-codex-pass.sh:1274-1303 (observed: 2026-10-31)
- Own-lane call sits in the rebase check only -- scripts/builder-codex-pass.sh:1713-1720 (observed: 2026-10-31)
- Drift line; test approval line -- templates/rules-details.md:41, templates/test-rules.md:13, templates/main-rulings.md:16, templates/_builder-brief-template.md:123 (observed: 2026-10-31)

## Plan change log

- 2026-10-31: first version.
- 2026-10-31 owner: yes to setup-gate.test.sh:35 and builder-codex-pass-test-edit.test.sh:44; question closed, Owner's additions line added.
- 2026-10-31 close reasons: #492, #500, #501, #508 carry comment and retest under Merge; each retest rerun today; none needs the owner.
- 2026-10-31 no new flag (revise rule): `--clear-failure` removed, main removes the record; `--edited-tests` became test-edit-labels.sh, so new-test-count.sh and its test stay as they are; `COMMANDECK_SHELL_TEST_LOAD` removed, tests stub `uptime`.
- 2026-10-31 Sol P2 accepted: C1 uses `chmod +x`; core.filemode is true and the pass stages with `git add -A` at :1541.
- 2026-10-31 Sol P2 accepted: seat.sh:495 added to C1.
- 2026-10-31 Sol and Fable P2 accepted: C3 covers `HOOK_FIRE_BLOCK=1` refusals; four hooks have no `exit 2`.
- 2026-10-31 Sol P2 accepted: a line that is no `check` or `it(` block maps to `(file)`; Routing's label for :44 follows.
- 2026-10-31 Sol P2 accepted: the `.gitattributes` prefilter is gone; `git check-attr` decides.
- 2026-10-31 Sol P2 accepted: `generated-read-guard.sh` joins `READ_ONLY_KEEP`, with a test.
- 2026-10-31 Sol P2 accepted: the Stop key holds the checks file's cksum.
- 2026-10-31 Sol P2 and Fable P3 accepted: the tracked check reads the resolved target. A tracked `.claude` link makes this reachable from a clone, so Fable's "moot" does not hold.
- 2026-10-31 Fable P2 accepted: the third-start refusal prints no way past.
- 2026-10-31 Fable P2 accepted: `passes` is null and named, on every new row.
- 2026-10-31 Sol and Fable P3 fixed: `Catches:` on C5, C7-C11.
- 2026-10-31 Fable P3 fixed: 14 fixture users; main-session.md and ask-stop-records-decision.sh in C1; tab-separated record; hook rules in Protocols; C10 says where a check runs.
- 2026-10-31 Fable's Builder guesses settled: label parsing, the job formula, slug rule, verdict words.
- 2026-10-31 Sol r2 P2 accepted: `seconds:` is one deadline for the whole run; hook-on-failure.guard.test.sh:6 bars `onFailure` on Stop, so a per-command bound could overrun the entry's 135 s. New case: two commands share one deadline.
- 2026-10-31 Sol r2 P3 accepted: the lock joins `IL_STATE`, `.gitignore` and worktree-setup.sh:62; neither list held it (read today), and the host ignores it. Cost under five lines. New case: the lock stays out of a commit.
- 2026-10-31 added beside the P3: `.claude/stop-checks` joins `IL_STATE` and `.gitignore`, one word each: a tracked one is refused, so nothing should stage it.
- 2026-10-31 no finding was false. Fable's report file held no verdict, so its findings came from its session record.
- 2026-10-31 Builder, main agreed: `no test pins the old words` was false. Rewording main-session.md changes hashed rule ids (merge-rules.test.sh, agent-startup-context.test.sh), and C5's added rule passed plugin.test.sh's 200-line cap. main-session.md stays as on main, its `decision.sh` words stay bare; main's reset of `builder-pass-failed` moves to rules-details.md and docs/review-loop.md. No existing test edited for this.
- 2026-10-31 Builder, class-miss returned at pass 2: the label reader's `(file)` was a fall-through. It is now earned from a fixed list, anything else exits 2 naming the line (Data design, D5). Shell reads prove a contract only from a whole-file printer or an overlapping window (false-read-proof). Reviewed alone first. Recounted: the three checks the fix rounds added join the test lines, 76 again.
- 2026-10-31 owner: a line the reader cannot place stays refused; one `line:` approval unlocks that one line. Pass 3's indirect-helper P1 closed by a fixed point over the file's functions, and strict reading of a file that sources or evals: 98 of 238 test files source, so a closure cannot be complete there. `an it block maps to its label` folds into `a check line maps to its label` (new test file, every assertion kept) for `a line approval unlocks one line`: cap stays 76.
- 2026-10-31 Builder, r4 sweep: quoted globs, unfollowable `cd`s and `2 >` prove nothing (false-read-proof, not in the plan list); a cut Stop state line runs the checks again, as `${PR:-0}` read it green.
- 2026-10-31 owner, class-miss at pass 4: delete the list. Each pass found one more place where the reader judged code it could not see through (a shell wrapper, a sourced file, a JS helper), so a code line now gets its test's label or is refused with a `line:` approval, and `(file)` stays only for data files. Removes the fixed point, the opener list and the strict rule for sourcing files. Corrects the pass 3 claim that main's held `test:(file)` for :44 stays valid. Renames: `a data line maps to (file)`, `a helper edit needs its line`. A sweep find: a line holding two tests gives no label.
- 2026-10-31 Builder, pass 5: ran as a closing pass, not design-only, because the Builder committed the plan by hand; the pass reads a design only from a commit of its own. Its two P1s name unbuilt code.
- 2026-10-31 Builder: A2 red, #506 moved from Closes to Refs. Claim `PYTHONDONTWRITEBYTECODE removes every false tree changed line` is false for a full run: 204 lines on the Mac run with it set. The cause is not found.

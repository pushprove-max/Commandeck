# Plan: plugin-open-issues-2026-10-26: every open plugin issue in one unit, plus the setup-defaults order

Owner's words: every open plugin issue goes into ONE unit, no split, whatever the size caps say.

Addition the owner approved by name (the setup-defaults order, same unit): "setup shows limited options and efforts; the
config has many more. Make setup offer them all, with the recommended values taken from the host's current configured
settings."

Closes: issue 341, issue 351, issue 355, issue 362, issue 364, issue 368, issue 369, issue 371, issue 372, issue 373,
issue 374
Closes (no code; the stall mechanic stays removed, main answer 1): issue 349

- Planned size: 43 files, 1355 changed lines

Tier: Standard. LOCAL merge only. Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no red
proofs, no `Mutation-verified:` line, no test-timeout raises. Tests run on the PC. One unit, no split.

Timed checks: `scripts/__tests__/answer-worker.test.sh` (`timeout 8` at :161), `scripts/__tests__/to-main.test.sh`
(`timeout 3` at :78), `scripts/__tests__/builder-fresh-round.test.sh` (`timeout` at :46 :108 :177),
`scripts/__tests__/builder-codex-pass-fresh-round.test.sh` (`timeout 30` at :94). The one heavy case this unit adds, two
passes started together on one worktree (C5, in `scripts/__tests__/builder-codex-pass.test.sh`, a file with no timed
check), goes after that file's existing lock checks (:73-84). New cases in the four timed files go after their existing
timed checks, and each sets its own short wait (`ANSWER_WORKER_ACK_WAIT=2`, `COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0`).

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

- L1. The new-package guard's run time. Today it averages 179 ms on the setup command that issue 372 reports and 155 ms on
  `cd x && npm install lodash` (20 runs each: `for i in $(seq 20); do bash hooks/dependency-addition-guard.sh <<<"$P";
  done`, timed with `perl -MTime::HiRes`, 2026-10-26); `python3 -I` starts in 35 ms on the same machine (same method).
  The rewritten guard stays at or under 180 ms on those two payloads. Its speed is not otherwise judged.
- L2. Saved answers to the old "Review rounds" question on this machine: 0. Command, 2026-10-26: every `settings.json`
  under the Claude config folders read with `jq '.pluginConfigs'` (only one plugin's options are saved there, none of
  this plugin's), and `find "$HOME" -maxdepth 7 -name commandeck.json | xargs grep -l '"maxRounds"'` (no file). So no
  compatibility path is planned for `maxRounds` or `maxReviewRounds` (issue 373, the order's rule).
- L3. The option count: 41 userConfig keys today (`jq '.userConfig | length' .claude-plugin/plugin.json`, 2026-10-26).
  After this unit: 43 (issue 373 takes one away and adds three).
- L4. Programs whose quoted argument the guard reads as code: none (the owner's ruling after plan pass 4). An install
  handed to another program as text passes: `bash -c '...'`, `sh -lc`, `eval '...'`, a wrapper's program
  (`sudo bash -c`), a shell's option operands, a heredoc body or here-string a shell reads (`bash <<'EOF'`,
  `cat <<'EOF' | bash`, `> >(sh)`), `watch`, `ssh`, `su -c`, a script that runs its argument. The guard is a tripwire
  against forgetting to ask, not a security boundary (`hooks/dependency-addition-guard.sh:27-32`); a finding that needs
  one of these forms is out of scope.

## 1. Item map (what exists, what this unit adds, the test)

| Issue | What exists (file:line) | What this unit adds | Cut |
|---|---|---|---|
| 341 | Data design in briefs (`scripts/builder-launch.sh:85-88`), finding history in fix briefs (`scripts/builder-codex-pass.sh:1598-1622`), the redesign trigger (`:1590-1640`), a per-finding "failure table" check (`:1604-1605`, `:1623`) | The failure table the issue asks for: one row per save, its steps, what is left if the work stops after each step, the one recovery; required before review pass 1 for a unit that stores data; the per-finding class check is replaced by a per-save rule | C8 |
| 349 | Band, side pane, status line, toggles and `/units` (`hooks/units.tsx`, `hooks/units-sources.ts`); `ageSec` per unit row (`hooks/units-sources.ts:91,140`, from `seat_age`, `scripts/dashboard.sh:128-143`); a test that asserts no stall mark (`hooks/units-panes.test.tsx:93-99`) | Nothing to build: the stall mechanic stays removed (the owner's order of 2026-10-25; main answer 1). The no-stall test stays; the closing comment says so | none |
| 351 | `--resume` reads the full inbox view (`scripts/ask-main.sh:23-27`); a timed-out question tells main once (`:44-50`); `--interrupt` (`scripts/answer-worker.sh:28-31,69-85`) | `answer-worker.sh` keeps checking a queued answer until the Builder reads it (its tag in the pane's log), and tells main when it never does | C9 |
| 355 | Loud skip of the hand-off (`scripts/builder-codex-pass.sh:1561-1570`, `no_handoff` :1324-1330); round taken from the `fix-r<N>` name (`scripts/builder-fresh-round.sh:113-114`); the switch and the `fixer=` record (:115-141) | The switch on a plain `<unit>-handoff.md` when the unit is in a fix round; a NO-GO pass run outside the Builder's pane hands the fix round to the Builder's pane, so the switch and the record happen every round | C6 |
| 362 | `Sites checked` gate (`scripts/builder-codex-pass.sh:1084-1093`), first-return redesign (:1590-1597), Test:-line and size checks (`scripts/builder-launch.sh:106-132`) | A `Break:` gate before review pass 1; a small unit that a risky trigger sends to the Panel gets one plan judge | C7 |
| 364 | The `pass-loop` alert (`scripts/dashboard_alerts.jq:66`, test `scripts/__tests__/dashboard-alerts.test.sh:81-85`); the unfinished-work Stop hook with its tests, unregistered (`hooks/cos-unfinished-stop.sh`, `hooks/__tests__/cos-unfinished-stop.test.sh:35-49`, `docs/hooks.md:37`) | Nothing to build: every part that does not contradict the owner's order is in. The hook stays unregistered; the closing comment says so | none |
| 368 | `pp_seat_pane` honours `COMMANDECK_MAIN_PANE_DIR` (`scripts/paths.sh:996`); test `scripts/__tests__/to-main.test.sh:221-224` | The launch records the launching main's checkout in the Builder worktree's env; a send that queues says plainly that main will not see it | C10 |
| 369 | The pass lock (`scripts/builder-codex-pass.sh:923-936`), released by `unlock` (:928, :936, :1340) | Taking and releasing the lock under one `flock` guard; release only by the pass that holds it | C5 |
| 371 | No commit guard in the plugin: `COMMANDECK_ALLOW_AGENT_GIT` is set by the pass (`scripts/builder-codex-pass.sh:1181,1208`) and read by no plugin file (`rg -n COMMANDECK_ALLOW_AGENT_GIT` lists only those lines) | `hooks/git-safety.sh` refuses `git commit` in a Builder pane; the refusal names a model co-author trailer when the message carries one | C11 |
| 372 | The install decision: `ran` (`hooks/dependency-addition-guard.sh:64-87`), `own_setup` (:93-100), `no_bodies` (:111-125), `whole` (:129-132), the matchers (:220-255) | One function, `bash_code`, a real shell-word split: quoted text and heredoc bodies are data, `$(...)` and backticks are code; code given as text is the stated limit L4 | C1 |
| 373 | The rule as constants: `REVIEW_CAP=5` (`scripts/builder-codex-pass.sh:387`), the P2 line in `holds()` (:357-358), `p2_count` (:394), the P3 line in `open_findings` (:620), the fresh closing reviewer (:1306-1312, the skip at :703); the old question (`skills/setup/SKILL.md:234-235`) | Three setup answers the pass reads: blocking severity (P2), pass cap (5), fresh closing reviewer (on); the old question and every reader of its option gone | C3 |
| 374 | `[ -n "$TEST" ] \|\| FULL=false` (`scripts/setup.sh:244`); a non-`--option` answer goes to `/config` only where `/config` has none (`scripts/install-lib.sh:476`) | An explicit On with no test command is refused, naming the missing answer; this run's explicit review-loop answers replace `/config`'s | C2 |
| order | Setup asks 2 to 4 values per role (`skills/setup/SKILL.md:111-162`); `--option` takes role keys only (`scripts/setup.sh:281`) | `config/recommended.json`, the one recommended-profile file; `setup.sh --recommended`; `--option` for every userConfig key; setup asks "Recommended set", then groups; every allowed value listed | C4 |

## 2. Cuts (build order)

Each cut: what it changes, Produces / Consumes, existing consumers of a contract it changes, size (changed lines,
code + tests + docs), acceptance tests (the named checks; "flip" is an existing check whose expected value changes).

### C1 -- issue 372: the new-package guard judges only what bash runs (~280 lines)

Where the guard decides a command is an install today: `hooks/dependency-addition-guard.sh:227` (`CMD=$(ran "$CMD")`)
feeds the matchers at :244-255; `ran` (:64-87) reads quoted text as data only on a line where every command is a sender
(:62) or the plugin's own `setup.sh` (:80, `own_setup` :93-100); any other line goes to `whole` (:129-132), which turns
every quote mark into a space, so `--test-command 'npm test' --global-rules install --rules merge` reads as
`npm test --global-rules install --rules merge` and the loose matcher (:240) sees `install merge`.

Reproduced 2026-10-26 (hook fed a Bash payload, first stderr line shown):

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --test-command 'npm test' --global-rules install --rules merge --plan  -> BLOCKED
bash scripts/setup.sh --test-command 'npm test' --global-rules install --rules merge --plan                          -> BLOCKED
bash <absolute path>/scripts/setup.sh  (same flags)                                                                   -> passes (own_setup)
foo --x 'npm install lodash'                                                                                          -> BLOCKED
cat <<EOF / npm install lodash / EOF   (unquoted end word)                                                            -> BLOCKED
cat > x <<'EOF' / npm install lodash / EOF                                                                            -> passes
npm install lodash                                                                                                    -> BLOCKED
cd x && npm install lodash                                                                                            -> BLOCKED
true; npm install lodash                                                                                              -> BLOCKED
echo $(npm install lodash)                                                                                            -> BLOCKED
bash -c 'npm install lodash'                                                                                          -> BLOCKED (today; passes after C1, L4)
```

The change, one function in the hook, no `lib/` helper in the decision path (so it ports to the host's twin guard as it
is): `bash_code <command>` runs one `python3 -I -c` program (standard library only) that splits the command into words
the way bash does and prints the code bash runs, one simple command per line, words joined by one space:

- Words: single quotes are literal; double quotes keep `\` escapes; `$'...'` is read as ANSI-C text; a backslash escapes
  one character; `#` at a word's start opens a comment. A word that had any quoted part is printed as its text when that
  text is one non-empty run with no blank, else as `$QUOTED` (the convention `strip_quoted` uses today, so the npm-ci
  folder reader at :156-204 and the package position at :235 read it as they do now: `npm install 'a b'` still blocks on
  `$QUOTED`).
- Separators end a simple command: newline, `;`, `&`, `&&`, `||`, `|`, `(`, `)`, `{`, `}` as reserved words. A
  redirection and its target are dropped (as :228 drops them today).
- Code inside data: the body of every `$(...)`, backtick pair, `<(...)` and `>(...)`, wherever it stands outside single
  quotes (a bare word, a double-quoted string, the body of a heredoc whose end word is unquoted, inside a `$((...))`),
  is split the same way and printed as its own lines; the word holding it prints as `$QUOTED`.
- Code given as text (`bash -c '...'`, `eval '...'`, a wrapper's program, a shell's option operands) is quoted text,
  so it is data (D2, the stated limit L4). No program word is read.
- Heredocs and here-strings: a body is data whoever receives it, a shell included (D2, L4). An unquoted end word makes
  only the body's substitutions code.
- What it cannot split (an unclosed quote, an unmatched `$(` or bracket, a heredoc with no end line, python3 missing or
  failing): it prints the command with every quote mark turned into a space (today's `whole`), so the worst case is a
  false block, never a missed install.

`ran`, `own_setup`, `no_bodies`, `whole`, `SENDERS` and the `lib/strip-quoted.sh` source line (:62-132) go: nothing else
in the hook calls them (`rg -n 'ran |own_setup|no_bodies|whole |SENDERS' hooks/dependency-addition-guard.sh`; the
Builder runs it after the edit and it must list only `bash_code`). `strip_quoted` stays in `lib/` for
`git-safety.sh` and `no-poll-loops.sh`. The approval prefix (:205-219), the npm-ci link check (:144-204) and the
matchers (:220-255) are unchanged and read `bash_code`'s output in place of `ran`'s. The header comment (:24-25, the
"accepted over-match class") is rewritten: quoted text and heredoc bodies are no longer judged.

The class (`rg -n 'npm|pnpm|yarn|pip' hooks/*.sh`, 2026-10-26), each other guard that matches package words in the raw
command string:

| Site | Verdict |
|---|---|
| `hooks/suite-rerun-guard.sh:150-158` | not affected: it already splits with `shlex` (`chain_segments`, :87-92) and matches only the words that run (:158) |
| `hooks/staged-index-warn.sh:32` | not affected: it only warns (strict tier), never blocks; a quoted `npm test` costs one warning line |
| `hooks/builder-event-log.sh:14` | not affected: it logs a test run's kind and never blocks a tool call (:6) |
| `hooks/bash-guardrails.sh:133-138` | not affected: an npm-first segment is skipped (an exemption), so a quoted word can only skip a check, never block |

Produces: `bash_code` (stdout contract: one simple command per line, quoted multi-word text as `$QUOTED`).
Consumes: nothing new. Existing consumers of the changed contract (the text `ran` printed): the npm-ci loop (:157, :203)
and the matchers (:227-253), both in this file. No other file sources this hook.

Acceptance tests (`hooks/__tests__/dependency-addition-guard.test.sh`):
- new: "setup with --test-command 'npm test' and install answers passes, named through ${CLAUDE_PLUGIN_ROOT}"
- new: "setup with --test-command 'npm test' and install answers passes, run by a relative path after cd"
- new: "a quoted option value that names an install passes" (`foo --x 'npm install lodash'`)
- new: "a heredoc body with an unquoted end word naming an install passes"
- new: "a real install still blocks: alone, after cd x &&, after ;, inside $(...), inside double-quoted $(...), inside backticks"
- new: "an install inside a heredoc body's $(...) still blocks"
- new: "a command with an unclosed quote is read whole and an install in it still blocks"
- flip: "another setup.sh with the same flags still blocks" (:133) becomes "any script's quoted answers are data" (0)
- flip: the five issue-311 scoping checks that exist only to fence `own_setup` (:158-161, :166-167, :169-170) become one
  check that the same commands pass; the checks that an install beside setup still blocks (:135-138, :156-157) stay as
  they are
- flip (the owner's ruling after plan pass 4): the heredoc run-by list (:183-186) and "a quoted install run by bash -c
  beside the plugin's setup still blocks" become "code given as text is data, the guard's stated limit" (0)
- new: "a substitution inside arithmetic still blocks", "a substitution in a shell's double-quoted -c text still blocks"
- kept: every other check in the file

Break: hooks/__tests__/dependency-addition-guard.test.sh -- a real install still blocks: alone, after cd x &&, after ;, inside $(...), inside double-quoted $(...), inside backticks -- hooks/dependency-addition-guard.sh bash_code (the code-in-data branches)

### C2 -- issue 374: setup never drops a Full suite "On" silently (~45 lines)

Cause, verified by reading: `scripts/setup.sh:244` sets `FULL=false` whenever no test command is set, whatever was
asked; and `il_plugin_options` (`scripts/install-lib.sh:476`) adds setup's non-`--option` answers to `/config` only
where `/config` has none, so a `false` an earlier run left in `/config` beats a later On (it prints a `note:` line,
:473-474, which the skill does not read back). `pp_option fullSuiteBeforeFinal` (`scripts/paths.sh:1143`) reads `/config`
first, so `/config` shows off.

The change in `scripts/setup.sh`:
- `--full-suite on` given this run with no test command (none given and none saved) stops setup: `die "--full-suite on
  needs a merge check: the closing pass runs that command. Answer the Merge check question (--test-command '<cmd>'), or
  --full-suite off. Nothing was changed"`.
- A saved On with no test command (no `--full-suite` this run) is set off and setup says so in the plan and the
  summary: `NOTES+=("Full suite before the final review: off, as no merge check command is set")` in place of the
  silent `:244`.
- The review-loop answers given on this run's command line (`--full-suite`, `--closing-pass`, and C3's three) go into
  `GIVEN` (`:195`'s object), so they replace `/config`'s value as `--option` answers do (`il_plugin_options`' third
  argument); answers carried over from the saved file keep today's "where `/config` has none" rule.

Produces: the refusal line above; `GIVEN` now also holds `fullSuiteBeforeFinal` and `closingPass` when given.
Consumes: `il_plugin_options` (unchanged). Existing consumers of `GIVEN`: the role-key loop (`:274-290`), which must
skip non-role keys (C4 widens it to every userConfig key), `il_plugin_options` (`:464`), `il_main_model` (`:466`).

Acceptance tests (`scripts/__tests__/setup.test.sh`):
- new: "--full-suite on with a test command leaves fullSuiteBeforeFinal true where /config reads it, over an earlier false"
- new: "--full-suite on with no test command refuses, naming the merge check, and writes nothing"
- new: "a saved On with no test command is set off and the plan says why"
- update: `skills/setup/SKILL.md:185` ("with None, skip this: setup records Off and says so") stays true; docs line in
  `docs/setup-questions.md:21` adds "On needs a merge check; setup refuses On without one".

Break: scripts/__tests__/setup.test.sh -- --full-suite on with no test command refuses, naming the merge check, and writes nothing -- scripts/setup.sh the --full-suite refusal

### C3 -- issue 373: the review workflow is three setup answers the pass reads (~230 lines)

The rule lives in `scripts/builder-codex-pass.sh` as constants: `REVIEW_CAP=5` (:387, read at :403, :659, :987-988,
:1540-1542), the blocking line in `holds()` (`min(levels) < "3"`, :357-358), `p2_count` (:394, read at :662, :1541), the
non-blocking P3 reader in `open_findings` (:620), the reviewer prompt (`VERDICT: GO when you list no P0, P1 or P2
finding`, in `GUIDANCE` :114), the threshold stop message (:1538), and the fresh closing reviewer (:1306-1312; the
earlier-findings check skipped for it at :703).

New answers (setup flags; `reviewLoop` keys in `.claude/commandeck.json`; userConfig keys, which beat the project's as
`closingPass` does, `scripts/paths.sh:1052-1053`):

| Answer | Flag | reviewLoop key | userConfig key | Values | Default |
|---|---|---|---|---|---|
| Blocking severity | `--block-at P1\|P2\|P3` | `blockAt` | `reviewBlockSeverity` (string, options P1, P2, P3) | P1, P2, P3 | P2 |
| Pass cap | `--pass-cap <n>` | `passCap` | `reviewPassCap` (number, min 1) | whole number >= 1 | 5 |
| Fresh closing reviewer | `--fresh-closing yes\|no` | `freshClosing` | `freshClosingReviewer` (boolean) | yes, no | yes |

What the pass reads: `BLOCK=$(pp_review_loop blockAt P2 '^P[123]$')`, `REVIEW_CAP=$(pp_review_loop passCap 5
'^[1-9][0-9]*$')`, `FRESHC=$(pp_review_loop freshClosing yes '^(yes|no)$')`, all near :440. Each constant site becomes:
- `holds()`: a line holds the loop when its lowest level is at or below `BLOCK`'s digit (passed into the Python as an
  argument, as `$REVIEW_CAP` is at :403).
- `p2_count` becomes `cappable_count`: lines whose level is P2 up to `BLOCK` (P0 and P1 are never capped, the owner's
  rule from issue 366, unchanged). With `BLOCK=P1` nothing is cappable, so a cap stop never fires; a P1 still stops for the
  owner at cap + 2 (`review_stop_id`, unchanged).
- `open_findings` (:620): the non-blocking lines are those above `BLOCK`.
- The prompt line and the messages at :659, :662, :1538, :1542 name the blocking levels from `BLOCK` ("P0, P1 or P2"
  stays the text at the default).
- `FRESHC=no`: the closing pass is handed the review history like any pass (:1312's clearing is skipped) and the
  earlier-findings check runs for it (:703).

The old question and every reader of its saved option (`maxRounds` / `maxReviewRounds`) and what each becomes:

| Reader | Becomes |
|---|---|
| `scripts/builder-codex-pass.sh:881` (`MAX_ROUNDS=$(pp_review_loop maxRounds ...)`) | removed; `MAX_ROUNDS` is set only by the unit's `<unit>-review-cap.md` (`review-cap.sh`, main's per-unit limit, :897-903, unchanged) |
| `scripts/builder-codex-pass.sh:897` (`LIMIT_FROM` text naming `reviewLoop.maxRounds`) | names `review-cap.sh for <unit>` only |
| `scripts/builder-launch.sh:295-297` (`MAXR`, the "at most N rounds" brief line) | removed; the brief's loop line states the pass cap, the blocking levels and whether the closing reviewer is fresh, only when one differs from its default (with every default the brief reads as today) |
| `scripts/paths.sh:1052` (`pp_review_loop`'s `maxRounds` -> `maxReviewRounds` case) | the three new keys: `passCap` -> `reviewPassCap`, `blockAt` -> `reviewBlockSeverity`, `freshClosing` -> `freshClosingReviewer` (boolean read as yes/no, as `closingPass` at :1083) |
| `scripts/paths.sh:1142` (`pp_option maxReviewRounds`) | the three new keys with their `reviewLoop` paths and defaults |
| `scripts/setup.sh:10, :56, :220, :461` (usage, `TAKES`, `--max-rounds`, the `/config` write) | the three new flags; `--max-rounds` is gone (an old call gets the usage line) |
| `.claude-plugin/plugin.json` `userConfig.maxReviewRounds` | removed; the three new keys added |
| `skills/setup/SKILL.md:230, :234-235` | the Review workflow group of C4 (no "No cap" anywhere) |
| `docs/configuration.md:70-76` | the three keys, their defaults, and that `review-cap.sh` is main's per-unit round limit |
| `scripts/__tests__/plugin.test.sh:64`, `scripts/__tests__/plugin-option.test.sh:53-58`, `scripts/__tests__/fixtures/builder-codex-pass-setup.sh:103` | rewritten for the new keys; the fixture's `maxRounds` goes (tests that need more rounds already raise them with `review-cap.sh`) |

How setup knows the new questions are unanswered (an existing install is asked them at its next run): `setup.sh
--questions begin` (`scripts/setup.sh:142-180`) prints `  review workflow: not answered (blocking severity, pass cap,
fresh closing reviewer): ask them` when `reviewLoop` has none of `blockAt`, `passCap`, `freshClosing` and `/config` has
none of the three keys; the run's summary adds a `NEED` line the same way as the cache answers (`:474-476`). The skill
asks the Review workflow group whenever that line is printed, even on "Keep saved".

Produces: `reviewLoop.blockAt|passCap|freshClosing`; userConfig `reviewBlockSeverity`, `reviewPassCap`,
`freshClosingReviewer`; setup flags `--block-at`, `--pass-cap`, `--fresh-closing`.
Consumes: `pp_review_loop`, `pp_config_option` (unchanged shape).
Existing consumers of changed contracts: `REVIEW_CAP` readers (:403, :659, :987-988, :1540-1542); `merge-unit-local.sh`
reaches the rule only through `builder-codex-pass.sh --verify` (`:272`), whose comment at :246-247 is updated; the
dashboard and units mod read verdicts, not the threshold (`rg -n 'REVIEW_CAP|P0, P1 or P2' scripts hooks` lists no
other reader).

Acceptance tests:
- `scripts/__tests__/builder-codex-pass-threshold.test.sh` new: "with blockAt P3 a lone P3 holds the merge"; "with
  blockAt P1 a lone P2 ends the loop GO"; "the reviewer prompt names the blocking levels from blockAt"
- `scripts/__tests__/builder-codex-pass-closing.test.sh` new: "with passCap 3 a closing NO-GO naming only a P2 cap-stops at
  pass 3 on record, not before"; "with freshClosing no the closing pass is handed the earlier findings and checked for them"
- `scripts/__tests__/plugin-option.test.sh` rewritten: "the review loop reads blockAt, passCap and freshClosing from the
  project, and /config's keys beat them"
- `scripts/__tests__/setup.test.sh` new: "an install with no review workflow answers is asked them"; "the chosen pass cap
  reaches the review script" (setup `--pass-cap 7`, then `pp_review_loop passCap` prints 7); "--max-rounds is refused"
- `scripts/__tests__/plugin.test.sh`: "no option, flag or question text offers No cap" (`grep -c 'No cap'` over SKILL.md,
  setup.sh and plugin.json is 0)

Break: scripts/__tests__/builder-codex-pass-threshold.test.sh -- with blockAt P3 a lone P3 holds the merge -- scripts/builder-codex-pass.sh holds()

### C4 -- the setup-defaults order: a recommended set, then groups; every option reachable (~280 lines)

1. `config/recommended.json` (new), the one recommended-profile file: `{"note": "<one line>", "options": {<key>:
   <value>}}` holding a value for each key of "Recommended profile" below. Values are model ids, effort
   words, numbers, booleans and an option's own fixed words (`auto`, `1h`, `P2`); no path, address, name or spend (the
   order, point 4). It leaves out five keys that setup asks by their own questions: `codexReviewerAgent` and
   `planJudgeSolAgent` (the Reviewer question picks the profile), `fullSuiteBeforeFinal` (it needs a merge check, C2),
   `dashboardBind` and `dashboardPort` (the Dashboard question; an address is this machine's).
2. `scripts/setup.sh --recommended`: before the argument loop, `--recommended` is replaced by the flags the profile
   gives, placed before the other arguments so any later flag wins: `--option <key>=<value>` for each key, except the
   keys with their own flag (`mainPromptCacheTtl` -> `--main-cache-ttl`, `workerPromptCacheTtl` -> `--worker-cache-ttl`,
   `relayPromptCacheTtl` -> `--relay-cache-ttl`, `closingPass` -> `--closing-pass yes|no`, and C3's three). A model value
   the role's agent does not take this run (a Codex id for a reviewer on the Claude profile), or a Codex fast key the
   Codex home cannot take (`pp_codex_fast_home`), is left out and named in the plan output
   (`recommended <key>=<value> skipped: <why>`), never a refusal.
3. `--option` takes every userConfig key, not role keys alone (`scripts/setup.sh:281`): a role key is checked as today
   (`pp_role_option`); any other key is checked against the manifest: an `options` list, a `number` (whole, at or above
   its `min`), a `boolean` (true or false, saved as one, as :283-286 does), `wakeKinds` (comma list of the kinds
   `scripts/paths.sh:1158` takes). A value it does not take stops setup naming the key and the values it takes.
4. `setup.sh --questions begin` prints, for every profile key, `  recommended <key>: <value> (takes: <every allowed
   value>)`, read from the profile and the manifest, so the skill shows recommended values and allowed lists from code,
   never from its own text.
5. `skills/setup/SKILL.md`: step 6's per-role questions (:111-162), step 11's three cache questions (:193-206) and step
   13 (:228-248, the review loop's tune questions; the review flags `--max-review-min` etc. stay as a group) become:
   - Ask "Settings": Recommended set (recommended) | Choose groups | Keep saved
     - Recommended set: every setting from the plugin's recommended profile, listed by the preview. `--recommended`
     - Choose groups: `--recommended`, then each chosen group's answers override it.
     - Keep saved: sends none of these flags.
   - On "Choose groups", two multi-select questions (`multiSelect: true`), up to four groups each:
     Ask "Groups": Models | Plan seats | Reviewer | Review workflow
     Ask "More groups": Caches | Builders and wakes | Units views | Auto-decide
   - Each chosen group asks each of its keys once, up to four per call: the question names every value the key takes
     (the `takes:` list `--questions begin` printed), its options are the recommended value first, then up to three
     others; the picker's own text answer takes any other listed value. Sent as `--option <key>=<value>` (or the key's
     own flag, as in point 2).
   - Groups: Models (`orchestratorModel`, `orchestratorEffort`, `builderModel`, `builderEffort`, `fixerEnabled`,
     `fixerFirstModel`, `fixerFirstEffort`, `fixerModel`, `fixerEffort`); Plan seats (`planAuthor*`, `planJudgeSol*`
     but its agent, `planJudgeFable*`); Reviewer (`codexReviewerModel`, `codexReviewerEffort`, `codexReviewerFast`);
     Review workflow (C3's three, `closingPass`, and the existing small-build and review-flag questions); Caches (the
     three cache keys); Builders and wakes (`maxBuilders`, `wakeKinds`, `wakeWindowSeconds`); Units views (the three
     view keys); Auto-decide (`autoDecideSeats`).
   - The Review workflow group is asked whenever `--questions begin` printed `review workflow: not answered` (C3).
   The questions that set no userConfig key stay as they are (Reviewer, Permissions, rules, Context, clear line, issue
   sizing, Trust hooks, Relay, Dashboard, Merge check, Full suite, Strict, Auto mode, worker cuts, add-ons).
6. Docs: `docs/setup-questions.md` rows "Builder model, context", "Builder effort", the three cache rows, "Review loop",
   "Plan models, plan fast", "Codex fast, Codex model" become "Settings" (recommended set or groups, every value listed)
   and "Review workflow"; README's "What setup asks" table (`README.md:93-126`) gets the same rows.

Produces: `config/recommended.json` (read by `setup.sh` only); `setup.sh --recommended`; `--option <any userConfig
key>`; the `recommended <key>:` lines of `--questions begin`.
Consumes: C3's keys, `pp_codex_fast_home`, `pp_role_option`.
Existing consumers of changed contracts: `--option`'s callers are the skill and the tests (`scripts/__tests__/setup.test.sh`,
`scripts/__tests__/plugin.test.sh:76-79`); the `plugin.test.sh` table (:56-78, an option's default equals SKILL.md's
recommended answer) loses its rows for profile keys (see Decisions D9); the 2-to-4 options check (:96-100) and the
"every option key SKILL.md names is a manifest option" check (:76-79) keep running over the new text.

Acceptance tests:
- `scripts/__tests__/plugin.test.sh` new: "every userConfig option is set by the recommended profile or asked by setup,
  none orphaned" (each manifest key is a key of `config/recommended.json`, or SKILL.md names it in an `--option <key>=`
  or its own flag, or it is one of the five keys of point 1 with its question named); "every profile value is one its
  key takes" (each value checked as `--option` checks it); "the profile holds no path, address or name" (no value holds
  `/`, `@`, a dot-quad, or a space)
- `scripts/__tests__/setup.test.sh` new: "setup --recommended saves every profile value to /config"; "a later --option
  beats --recommended"; "a Codex model in the profile is skipped and named on the Claude profile"; "--option
  unitsBand=sometimes is refused naming auto, on, off"; "--questions begin lists every profile key with its takes list"
- `scripts/__tests__/plugin.test.sh` kept: the 2-to-4 options check and the manifest-key check over the new SKILL.md

Break: scripts/__tests__/setup.test.sh -- --option unitsBand=sometimes is refused naming auto, on, off -- scripts/setup.sh the --option check for non-role keys

### C5 -- issue 369: one pass holds the pass lock, and only it releases it (~50 lines)

Today (`scripts/builder-codex-pass.sh:929-936`): `mkdir` takes the lock and the pid is written after it, so a pass that
reads an empty pid in between takes the lock over as dead (:930-933); two takeovers can interleave (each `unlock`s and
`mkdir`s); and `unlock` (:928, run by `trap` :936 and `pass_end` :1340) removes whatever lock is there, a new holder's
included.

The change: every step that reads or changes the lock runs under `flock` on `<git dir>/builder-pass.lock.guard`
(`flock` is a stated requirement, `scripts/requirements.sh:188`, already used by `scripts/to-main.sh:21`). Taking: under
the guard, `mkdir`, then the pid written, then the guard released; a lock that exists is read under the guard, so its
pid is always written: a live pid refuses (today's message), a dead or missing one is taken over in the same guarded
step. Releasing: under the guard, the lock is removed only when its pid is this pass's `$$`; otherwise it is left and
nothing is said. The lock's shape (`builder-pass.lock/pid`, `/index`) is unchanged.

Produces: `<git dir>/builder-pass.lock.guard` (an empty file the guard locks; never removed).
Consumes: `flock`.
Existing consumers of the lock: `--verify`'s holder read (`scripts/builder-codex-pass.sh:628`), the staged-index copy
(:1131-1132), tests `scripts/__tests__/builder-codex-pass.test.sh:73-84` and
`scripts/__tests__/builder-codex-pass-fresh-round.test.sh:14`. None changes: the pid file is where it was.

Acceptance tests (`scripts/__tests__/builder-codex-pass.test.sh`, after :84):
- new: "two passes started together on a dead holder's lock: one runs and the other is refused"
- new: "the first pass's exit leaves the second's lock in place" (the stub reviewer of pass A writes a live pid of
  another process into the lock while A runs, as a takeover would; after A exits the lock and that pid remain)
- kept: :78-84 (a live holder refuses; a dead holder's lock is taken over and released)

Break: scripts/__tests__/builder-codex-pass.test.sh -- the first pass's exit leaves the second's lock in place -- scripts/builder-codex-pass.sh unlock's owner check

### C6 -- issue 355: the fixer setting applies every fix round, whatever the session shape (~85 lines)

1. A plain hand-off: `scripts/builder-fresh-round.sh:113` switches only for `<unit>-fix-r<N>.md`. Added: a
   `<unit>-handoff.md` (the context line's hand-off, `hooks/context-line.sh:24`) is a fix round when the unit's newest
   round file `<unit>-r<N>-reports.md` (highest N, in the hand-off's folder) ends `VERDICT: NO-GO` (the round file's last
   line is the verdict, `scripts/builder-codex-pass.sh:1523`); its round is that N, and the same switch and `fixer=`
   record run, after the `/clear` this script already types first (:104). After a GO round, or with no round file, a
   plain hand-off switches nothing (today's behaviour for it).
2. A pass run outside the Builder's pane: `scripts/builder-codex-pass.sh:1564-1570` skips the hand-off unless the pass
   runs in the Builder's own pane from its worktree. Changed for a NO-GO: the fix hand-off is written and
   `builder-fresh-round.sh` is started for the seat record's handle (`SEAT_HANDLE`, :1564), whoever ran the pass; the
   `where()` lines (:1572-1576) name that handle; the line printed to the caller says the Builder's pane takes the fix
   round (and says "end your turn" only when the caller is that pane). The hand-off is skipped, loudly as today
   (`no_handoff`), only when the seat record names no pane. A long GO pass (:1577-1586) keeps the own-pane rule: a pass run
   elsewhere grew no Builder context.
3. No `/model` without a `/clear` right before it in the same hand-off: both switch paths type `/clear` first (:104),
   and nothing else in the plugin types `/model` (`rg -n '"/model' scripts hooks` lists only :132).

Produces: `fixer=` lines for plain hand-offs in a fix round and for fix rounds started from another pane.
Consumes: round files, the seat record.
Existing consumers: main-watch and the dashboard read the record's last `model=`/`session=` lines (unchanged shape);
`scripts/__tests__/builder-fresh-round.test.sh:147-150` (a plain hand-off moves no model: becomes "after a GO round");
`scripts/__tests__/builder-codex-pass-fresh-round.test.sh:108-116` and
`scripts/__tests__/builder-codex-pass-class-sites.test.sh:33` (the skip reasons: they flip to a hand-off, and a new check
keeps the one skip left).

Acceptance tests:
- `scripts/__tests__/builder-fresh-round.test.sh` new: "a plain hand-off after a NO-GO round 3 switches to the later-round
  fixer and records fixer=later round=3"; "a plain hand-off after a NO-GO round 1 records fixer=first round=1"; flip
  :147-150 to "a plain hand-off after a GO round types no /model"; new "every /model in every run's typed sequence comes
  right after /clear"
- `scripts/__tests__/builder-codex-pass-fresh-round.test.sh` flip :108-113: "a NO-GO pass with no Orca handle hands the fix
  round to the Builder's pane"; "a NO-GO pass run from another pane hands the fix round to the Builder's pane"; new "a
  NO-GO with no pane in the seat record skips the hand-off and tells main"
- `scripts/__tests__/builder-codex-pass-class-sites.test.sh:33`: the fixture's skip comes from a seat record with no
  handle (Builder check B5)

Break: scripts/__tests__/builder-codex-pass-fresh-round.test.sh -- a NO-GO pass run from another pane hands the fix round to the Builder's pane -- scripts/builder-codex-pass.sh the hand-off gate

### C7 -- issue 362: the Break gate before pass 1, and one judge for a small risky unit (~85 lines)

1. Break gate (`scripts/builder-codex-pass.sh`, beside the evidence gates at :1013-1018, run when `KIND=adversarial` and
   no round file of the unit exists yet): every `Break: <test file> -- <check label> -- <site>` line of the plan (outside
   fenced blocks; `plan_file`, :995) needs a line in the evidence file's `## Break runs` section: `- <test file> --
   <check label> -- red: <command that ran it with the condition removed>`. Missing ones are listed in one refusal, with
   the line to write. A plan with no `Break:` line, or no plan, owes nothing.
2. One judge for a small risky unit (`scripts/plan-tier.sh:21-33`): the batch's `## The batch` section may carry
   `Estimated size: ~<n> changed lines`. A Panel pick with an estimate under 150 becomes "Plan + judge" with the reason
   `<trigger>, a small unit (~<n> changed lines, under 150): one judge`; no estimate, or one at 150 or more, stays Panel
   (one tier up when unsure, the script's rule). The no-revise half already holds: a plan under 150 planned lines judged
   NO-GO by the Sol judge alone takes main's rulings in place of a revision (`scripts/builder-launch.sh:183-194`).
   `templates/_batch-brief-template.md` gets the optional line.

Produces: evidence section `## Break runs`; batch line `Estimated size:`.
Consumes: the plan's `Break:` lines (`scripts/seat.sh:416` already asks plan authors for them).
Existing consumers: `templates/_builder-brief-template.md` (step text before pass 1, one paragraph added); plan-tier's
output is read by main (`templates/main-session.md:58-71`, unchanged wording: it prints the tier).

This unit's own passes run main's installed plugin scripts, not the worktree's (`scripts/builder-launch.sh:289` puts
`$PP_SCRIPTS_Q` into the brief), so the new gate does not bind this build, and the order's "no red proofs" stands.

Acceptance tests:
- `scripts/__tests__/builder-codex-pass.test.sh` new: "pass 1 refuses when a plan Break line has no recorded break run,
  naming it"; "pass 1 runs when every Break line has a red break run"; "a plan with no Break line owes nothing"
- `scripts/__tests__/plan-tier.test.sh` new: "a security batch estimated at ~120 changed lines gets one judge";
  "estimated at ~200 it stays Panel"; "with no estimate it stays Panel"

Break: scripts/__tests__/builder-codex-pass.test.sh -- pass 1 refuses when a plan Break line has no recorded break run, naming it -- scripts/builder-codex-pass.sh the Break gate

### C8 -- issue 341: the failure table as the issue asks, before pass 1 (~75 lines)

1. Shape (`templates/_builder-brief-template.md:21`, `:55`): `## Failure table` in the evidence file is one row per
   save: `| Save | Steps | Left behind if it stops after each step | The one recovery |`.
2. Gate before pass 1 (`scripts/builder-codex-pass.sh`, with C7's gate): when the unit's brief's `## Data design`
   section does not start with `none`, the evidence file needs a `## Failure table` with at least one data row of four
   cells (header and separator rows aside); else the pass refuses with the row shape. A unit with "none: <why>" owes
   no table.
3. The fix brief (:1604-1605, :1623): the per-finding check "classes not yet in the failure table" goes; in its place one
   line: "a fix that touches a save updates that save's row (steps, what is left after each, recovery) in the same
   commit; the next reviewer checks the code against the table".

Produces: the evidence `## Failure table` row shape. Consumes: the brief's `## Data design` (written at launch,
`scripts/builder-launch.sh:85-88`).
Existing consumers: `NEWCODE_HEAD` and the New code checked text (:178, :1017, :1617) name "the failure table" and stay
true; `FTAB`/`NOTAB` (:1604-1605, :1623) are their only readers and go; the reviewer's prompt reads the evidence file's
table as before.

Acceptance tests (`scripts/__tests__/builder-codex-pass.test.sh`): new "pass 1 refuses a unit with a data design and no
failure table row"; "pass 1 runs for a unit whose data design is none"; "a fix brief asks the save's row to change with
the fix and lists no classes"; any existing check of the "Classes not yet in the failure table" line flips (Builder
check B6).

Break: scripts/__tests__/builder-codex-pass.test.sh -- pass 1 refuses a unit with a data design and no failure table row -- scripts/builder-codex-pass.sh the failure table gate

### C9 -- issue 351: an answer queued behind a busy Builder is checked until it is read (~60 lines)

`scripts/answer-worker.sh:197-198`: after `ANSWER_WORKER_WAIT` (60 s) an inbox answer still unread returns 2 "queued,
not read yet" and nothing checks again; the background follower tells main only on exit 1 (:213). Changed: the queued
line is printed and the check goes on until the tag is in the pane's log (exit 0) or `ANSWER_WORKER_ACK_WAIT` seconds
from the send pass (default 600, longer than `ask-main.sh`'s 540-second question limit, `scripts/ask-main.sh:40`); the
existing "pane went idle with the inbox unread: type it once" step (:185-193) keeps running in that loop. At the limit:
`answer-worker: NOT acknowledged: ... still unread in <pane>'s inbox after <n>s` and exit 1, which the follower already
sends to main as a question (:212-213). Exit 2 is no longer returned.

Produces: `ANSWER_WORKER_ACK_WAIT`; the "NOT acknowledged" line. Consumes: `log_state`, `idle` (unchanged).
Existing consumers of the exit codes: the follower (:212-213, reads 1 only); the header comment (:17-20) and
`docs/troubleshooting.md:28` are updated; `scripts/__tests__/answer-worker.test.sh:60, :85` expect 2 and flip; no script
reads exit 2 (`rg -n 'answer-worker' scripts hooks` lists messages and comments only).

Acceptance tests (`scripts/__tests__/answer-worker.test.sh`, after :161-172):
- flip :60, :85: "an answer to a mid-turn pane that is never read ends NOT acknowledged (exit 1), after the queued line"
- new: "an answer read during the longer wait ends delivered (exit 0)"
- new: "in main's foreground an answer never read reaches main as one question"

Break: scripts/__tests__/answer-worker.test.sh -- in main's foreground an answer never read reaches main as one question -- scripts/answer-worker.sh confirm's acknowledgement limit

### C10 -- issue 368: a Builder reaches the main that launched it, wherever it runs (~55 lines)

1. `scripts/builder-launch.sh`, right after `worktree-setup.sh` (:366) and before the pane opens: the launching pane's
   checkout is read from `orca-ide terminal list --json` by `$ORCA_TERMINAL_HANDLE` (the same `wtp` field and `pnorm`
   that `pp_seat_pane` matches, `scripts/paths.sh:992-995`). When it differs from `$PP_MAIN`, it is written as
   `env.COMMANDECK_MAIN_PANE_DIR` in the Builder worktree's `.claude/settings.local.json`; when it is the same, or
   unreadable, the key is removed. A relaunch rewrites it. `pp_seat_pane` then finds that pane by its existing fallback
   (:996), so `to-main.sh` and `ask-main.sh` send to it.
2. `scripts/to-main.sh:30-36`: a message for main that queues says plainly that no main pane was found in `$WT` (or
   `COMMANDECK_MAIN_PANE_DIR`), that main does not see this queue until a main session starts in that checkout, and that
   a main running elsewhere must be told another way. `scripts/ask-main.sh:34` says the same for a queued question.

Produces: `env.COMMANDECK_MAIN_PANE_DIR` in a Builder worktree. Consumes: `pp_seat_pane`'s fallback (unchanged).
Existing consumers: `scripts/main-watch.sh:59,77` and `scripts/doctor.sh:140` read the variable from their own
environment, not from a worktree's settings (unchanged); `scripts/worktree-setup.sh` keeps unknown env keys on a rerun
(:76 deletes named keys only; Builder check B3).

Acceptance tests:
- `scripts/__tests__/builder-launch-resume-launch-line.test.sh` new: "a launch from a pane in another checkout records
  that checkout as COMMANDECK_MAIN_PANE_DIR"; "a launch from main's own checkout records none" (Builder check B3 picks
  the file)
- `scripts/__tests__/to-main.test.sh` new: "a Builder whose main runs in another checkout delivers to that pane, not to
  the queue" (env from the worktree settings, no `handles/main` file); "a queued send to main says main will not see it"

Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- a launch from main's own checkout records none -- scripts/builder-launch.sh the COMMANDECK_MAIN_PANE_DIR write

### C11 -- issue 371: no hand commit in a Builder pane (~35 lines)

`hooks/git-safety.sh`: the fast path (:17-18) admits `commit` only when `COMMANDECK_BUILDER=1`; the subcommand list in
`DISCARD` (:174) gains `commit`; the `case "$SUB"` (:280-316) gains `commit)`: in a Builder pane, `WHY="a Builder never
commits by hand: builder-codex-pass.sh commits what is staged, under its own message. Stage the work and run the
pass."`, plus `" This message also carries a model co-author trailer, which no Builder commit may carry."` when the
command text holds `Co-Authored-By:` naming Claude, Anthropic, Codex or OpenAI. Outside a Builder pane nothing changes.
The subcommand is found by the existing top-level option loop (`:266-274`), which skips the value of `-C -c --git-dir
--work-tree --namespace --config-env`; it gains `--attr-source` (r4 sweep: git 2.55 takes it with a separate value, so
`git --attr-source HEAD commit` read `HEAD` as the subcommand and the refusal missed it). git's other valued top-level
options (`--exec-path`, `--list-cmds`) take the value only after `=`, one word, already skipped by `-*`.
The pass's own commit (`scripts/builder-codex-pass.sh:1208`) runs inside the pass script, which the hook never sees (the
Bash call is `bash .../builder-codex-pass.sh`). `templates/_builder-brief-template.md:167` already says "Never commit
by hand"; `docs/hooks.md` gets one line.

Produces: the refusal. Consumes: `COMMANDECK_BUILDER` (set by `scripts/worktree-setup.sh:233`).
Existing consumers: none (a new check).

Acceptance tests (`hooks/__tests__/git-safety.test.sh`): new "a hand git commit in a Builder pane is refused"; "a git -C
<wt> commit in a Builder pane is refused"; "the refusal names a model co-author trailer when the message has one"; "a
commit outside a Builder pane passes"; "a git --attr-source HEAD commit in a Builder pane is refused"; "the pass
script's call in a Builder pane passes"
(`bash scripts/builder-codex-pass.sh u 2 review`).

Break: hooks/__tests__/git-safety.test.sh -- a hand git commit in a Builder pane is refused -- hooks/git-safety.sh the commit case

### C13 -- release (~35 lines)

Version: the next free minor at merge time (0.49.0 unless another unit took it first; `ci/version-check.sh` decides) in
`.claude-plugin/plugin.json` and the README badge; one CHANGELOG entry in the release-note style: topic sections named
for what a user sees, plain sentences, no file names, paths, issue numbers or hashes. Sections: "Setup", "Review
loop", "Builders and main", "Guards".

### C14 -- the public scrub: unit names, issue numbers and commit hashes allowed, spend figures checked (main answers 5, 6, 8) (~110 lines)

`ci/leak-words.txt`: the issue-reference pattern (`#` and three or four digits) goes; nothing banned a unit name or a
hash before, so nothing else goes. A secret-shape pattern (Anthropic key, AWS key id, GitHub token, a private key
block) is added, so a secret fails as the order says; the header lists what is allowed and what stays banned. Paths
under a person's home fail through the name pattern. `scripts/merge-unit-local.sh` step 4 already runs
`leak-test.sh --text` over the merge message, so its `(#N, ...)` references now pass with no code change.
`hooks/units-sources.test.tsx` drops the `hashes()` helper that only existed to dodge the ban. The Argon leak check is
a prompt in the operator seat's scratch folder, outside the repo: its rules 3 and 5 now say an issue number, a unit name and a
commit hash are not leaks. A spend figure fails by two patterns in `ci/leak-test.sh` (main answers 6 and 8), added to
the word list's patterns there, not in the word list, as the exemptions need them: a dollar sum with cents, comma
thousands or three or more digits fails anywhere (no shell parameter has three digits unbraced); a dollar sign and one
or two digits fails in text (`.md`, `.txt`, `.json`, the changelog, a `--text` message) and is taken out of a code
file's line as a shell or awk field, unless the digits run on into a figure. The changelog, exempt from the word
patterns, is searched for spend figures only. Then: the dashboard's seven test fixture
files, named in the script as real files only (not in `--text`), have only the figure taken out of a matching line, the
way the owner's name is taken out in the four named files, so anything else on that line still fails. Files that held
a figure are reworded: `skills/worktreereview/SKILL.md` (a measured cost) and three older plans (fixture values quoted
in prose become `<cost>` or "one cent"). For main answer 8: a shell parameter quoted in older plans' prose (a dollar
sign and a digit) gets braces, which bash reads the same; the documented review flag threshold becomes "30 US dollars" in four docs and two skills; the
changelog's tile figure becomes "zero" (31 hits in 19 files, rewritten by one script; no file exempted).

Acceptance tests (`scripts/__tests__/leak-test.test.sh`): new "a host unit name, an issue number and a commit hash
pass, in a file and in a message"; new "a path / a person / a ruling / a secret beside them still fails the message";
flip: the issue-number sample becomes the secret sample, and the png cases plant a banned name in place of an issue
number; kept: "the tree as committed is clean". Main answer 6: new "a spend figure in a doc / in a plan / in
thousands fails", "a spend figure fails a message (--text), where no fixture is exempt", "the same figures in a
dashboard fixture pass", "a banned name on a fixture's figure line fails", "a fixture name that is a link is searched
under what it holds", "a shell or awk field is no spend figure". Main answer 8: new "a whole sum of three digits in a
doc / in a script fails", "a whole sum of two digits in a plan fails", "a cents figure beside a field in a script fails",
"a spend figure in the changelog fails", "the changelog's other words stay exempt", "a whole sum of two digits fails a
message (--text)".

### C15 -- one precedence for every value setup saves (passes 5 and 6; main answers 7 and 9) (~150 lines)

Passes 5 and 6 found one class twice: setup kept a saved value over what the run asked for (the dashboard address, then
the reviewer's and Sol judge's models). The rule, stated once in `scripts/setup.sh` (above `stale_models`) and in
`docs/configuration.md`: this run's explicit answer (a flag or `--option`), then the profile or `--recommended`, then the
saved value. The sweep (evidence, "Sweep: every value setup saves") checked each saved value against it:

- `.claude/commandeck.json` (every field), the project record (scope, dashboard) and the machine's hosts: read saved,
  then each flag sets its variable, so the rule held; now tested field by field.
- `/config` keys: this run's answers ride in GIVEN, which `il_plugin_options` saves over /config, and every /config
  read in setup passes GIVEN; `--recommended` expands into `--option` pairs ahead of the owner's flags, so a flag after
  it wins. Broken and fixed: `--bind`/`--port` were not in GIVEN, so a saved /config address beat them (and
  `--option dashboardBind`/`dashboardPort`, pass 5, were read without GIVEN before the install). Both now go into GIVEN
  ('' is no answer), and the two reads before the install pass GIVEN.
- Seat models (pass 6, stale-model-on-profile-switch): `stale_models` runs once the profile has set the agent keys and
  before the role checks. For the reviewer and the Sol judge, an agent chosen this run with no model answered drops a
  saved model that agent cannot run (`model_ok`) back to routing's default (`project`), and the plan and summary name
  it. With no agent chosen this run, the saved pair is left to the preflight, as before.
- Kept outside the rule: an option the owner revoked with `revoke.sh` is left out even when this run answers it (only
  `revoke.sh` writes or clears that list, `il_plugin_options`); add-on installs of serena turn serena on.
- Found on the way: `setup.sh --plan` on a machine with no manifest stopped with exit 2 and no message
  (`il_profile_record` ran jq on the missing file under `set -e`); it now reads a missing manifest as no record.
- Found on the way: seven cases in `install-lib.test.sh` and `install-lib-setup.test.sh` failed since this unit's first
  round, as their harnesses pull setup.sh lines that round moved (the cache replay had no `GIVEN`; the full-suite case
  read a line `full_suite_rule` replaced; the key cases had no `opt_check`). The harnesses now pull the current lines,
  and the full-suite case checks a saved On with no test command (an On asked this run stops setup, `setup.test.sh`).

Acceptance tests (`scripts/__tests__/setup.test.sh`, setup.sh's own reads, full parse and commandeck.json build run on
hand-written saved files; no end-to-end run): "with no answer every saved value stands", "an explicit answer beats
every saved field (commandeck.json, the project, the machine) and the /config address", "an empty
--bind and --port are no answer", "--recommended beats a saved value for every profile key", "an explicit --option
after --recommended beats it for every profile key", the dashboard read cases, and the six `stale_models` cases
("--profile claude --recommended (the finding's run) ..."); `profile-revoke.test.sh` "a manifest that
does not exist yet is no record". By hand: the finding's `setup.sh --profile claude --recommended --plan` over a /config
holding the two Codex models ends 0 naming both resets.

### C0 -- issue 364 (no code)

Nothing to build. At merge main posts the closing comment: the pass-loop alert shipped in 0.48.0; the unfinished-work
Stop hook ships with its tests and stays unregistered by the owner's order until the owner says otherwise.

## Data design

- `reviewLoop.blockAt`, `reviewLoop.passCap`, `reviewLoop.freshClosing` in `.claude/commandeck.json`: written only by
  `setup.sh`; read by `pp_review_loop` in the pass and the launch; the userConfig keys beat them (one precedence,
  `scripts/paths.sh:1050-1053`). `''` takes the default back. No retry: a read that fails refuses the pass, as today.
- `config/recommended.json`: plugin file, read-only at run time, read by `setup.sh` only. One true copy; the next sync
  is one edit of it.
- `/config` options (`pluginConfigs` in the Claude settings): written by `il_plugin_options`; this run's explicit answers
  replace, carried-over ones fill only what is empty (C2).
- `env.COMMANDECK_MAIN_PANE_DIR` in a Builder worktree's `.claude/settings.local.json`: written by `builder-launch.sh`
  at each launch (set or removed), read through the environment by `pp_seat_pane`. A failed write stops the launch
  before the pane opens (the launch's existing write rule); a relaunch rewrites it.
- `<git dir>/builder-pass.lock/` and `<git dir>/builder-pass.lock.guard`: the lock is created and removed only under the
  guard, and removed only by its holder; a dead holder's lock is taken over under the guard. `flock` frees the guard when
  a pass dies.
- The seat record's `fixer=`, `model=`, `effort=` lines: appended by `builder-fresh-round.sh` (unchanged writer).
- The evidence file's `## Break runs` and `## Failure table`: written by the Builder, read by the pass gates.
- `answer-worker.sh`: no new state; its follower log is the existing one.
- The dependency guard's reader (`bash_code`): in memory for one hook call, nothing written. It keeps only the
  heredocs still waiting for their body on the current line (end word, quoted or not), emptied when the bodies are read;
  no runner, program word or receiver is kept (D2), so nothing from one command or line reaches another. Retry: the next call reads the command text again from nothing; the same text
  gives the same verdict whatever ran before it.

## Decisions

1. D1: The guard splits with its own Python reader, not `shlex` alone: `shlex` neither opens `$(...)` and backticks
   nor knows heredocs, and code inside data (`"$(npm i x)"`) must stay code.
   Test: dependency-addition-guard.test.sh "a real install still blocks: alone, after cd x &&, after ;, inside $(...), inside double-quoted $(...), inside backticks"
2. D2 (the owner's ruling after plan pass 4, which replaces the earlier D2 and main answer 3): the guard reads only
   what bash itself runs. Quoted text, here-strings and heredoc bodies are data whoever receives them; code handed to
   another program as text (`bash -c '...'`, `sh -lc`, `eval '...'`, a wrapper's program such as `sudo bash -c`, a
   shell's option operands, a body or here-string a shell reads, `cat <<'EOF' | bash`, `> >(sh)`) is data too, and an
   install hidden that way passes: the stated limit L4 (a tripwire, not a security boundary). No program word, wrapper
   table, runner flag or body receiver is read, so the reader keeps no state between commands or lines. What bash runs
   itself stays code: `$(...)`, backticks, `<(...)`, `>(...)` in a bare word, a double-quoted string (`bash -c
   "$(npm i x)"` blocks: the outer shell runs it first), an unquoted end word's heredoc body, and inside a `$((...))`.
   Test: dependency-addition-guard.test.sh "code given as text is data, the guard's stated limit" (`bash -c`, `sh -lc`,
   `eval`, `sudo bash -c`, `bash -o pipefail -c`, `bash <<<`, `bash <<'EOF'`, `cat <<'EOF' | bash`, `cat <<'EOF' >
   >(sh)`), "a substitution in a shell's double-quoted -c text still blocks", "a substitution inside arithmetic still
   blocks" (word, backticks, unquoted heredoc body) and "and is data in a quoted heredoc body", "a body after '<cmd>' is
   data" (earlier command on the same line, an earlier line, none), "an install inside a heredoc body's $(...) still
   blocks"
3. D3: An unreadable command fails closed (read whole, quotes as spaces).
   Test: dependency-addition-guard.test.sh "a command with an unclosed quote is read whole and an install in it still blocks"
4. D4: `own_setup` goes: a quoted answer is data for every script, so the setup exemption has nothing left to do.
   Test: dependency-addition-guard.test.sh "setup with --test-command 'npm test' and install answers passes, run by a relative path after cd"
5. D5: Blocking severity takes P1, P2 or P3; P0 and P1 always block and are never capped (the owner's issue 366 rule).
   Test: builder-codex-pass-threshold.test.sh "with blockAt P1 a lone P2 ends the loop GO"
6. D6: No compatibility path for the old `maxRounds` / `maxReviewRounds` answers (L2: 0 saved here); `--max-rounds` gets
   the usage line.
   Test: setup.test.sh "--max-rounds is refused"
7. D7: `review-cap.sh` stays main's per-unit round limit, separate from the pass cap.
   Test: none, its tests (`scripts/__tests__/builder-codex-pass-fresh-round.test.sh:30-41`) run unchanged
8. D8: The profile leaves out the two agent keys, `fullSuiteBeforeFinal`, `dashboardBind` and `dashboardPort`; each has
   its own setup question.
   Test: plugin.test.sh "every userConfig option is set by the recommended profile or asked by setup, none orphaned"
9. D9: `plugin.test.sh`'s rule that a manifest default equals SKILL.md's recommended answer (:56-78) is dropped for
   profile keys: their recommended value is the host's configured one in the profile, not a code default, and setup's
   "Recommended set" writes it to `/config`, so `/config` shows what setup recommended. Rows for the five keys asked by
   their own question stay.
   Test: setup.test.sh "setup --recommended saves every profile value to /config"
10. D10: A profile value the run cannot take (wrong agent, no Codex fast tier) is skipped and named, not refused: the
    recommended set must work on every profile.
    Test: setup.test.sh "a Codex model in the profile is skipped and named on the Claude profile"
11. D11: The relay has no model, effort or fast key (`jq '.userConfig | keys'` lists only `relayPromptCacheTtl` for it),
    so the order's "the relay" is met by its cache key in the Caches group; no new relay keys are planned.
    Test: plugin.test.sh "every userConfig option is set by the recommended profile or asked by setup, none orphaned"
12. D12: A NO-GO pass run outside the Builder's pane hands the fix round to the Builder's pane; a long GO pass run
    elsewhere does not.
    Test: builder-codex-pass-fresh-round.test.sh "a NO-GO pass run from another pane hands the fix round to the Builder's pane"
13. D13: A plain hand-off's round is the newest round file's N when it ended NO-GO; otherwise no switch.
    Test: builder-fresh-round.test.sh "a plain hand-off after a NO-GO round 3 switches to the later-round fixer and records fixer=later round=3"
14. D14: The answer is "acknowledged" when its tag is in the pane's session log (what the Builder printed), the test
    `confirm` already uses; Orca's per-message read state is not used (its field name was not seen: the inbox read on
    2026-10-26 held no message).
    Test: answer-worker.test.sh "an answer read during the longer wait ends delivered (exit 0)"
15. D15: The commit guard is a PreToolUse check in `git-safety.sh`, not a git hook: the plugin installs no git hooks and
    a project's own hooks would clash.
    Test: git-safety.test.sh "a hand git commit in a Builder pane is refused"
16. D16: The Break lines of this plan name the checks; this unit records no break run (the order: no red proofs; C7's
    gate does not bind this build, `scripts/builder-launch.sh:289`).
    Test: none, an order for this unit, not a behaviour
17. D17: The small-unit estimate comes from an optional batch line, not the plan: the tier is picked before a plan exists.
    Test: plan-tier.test.sh "a security batch estimated at ~120 changed lines gets one judge"

## Accepted failure modes

1. No program that runs a quoted string or a body is read (`bash -c`, `eval`, a wrapper's program, a shell reading a
   heredoc or here-string, a script, `watch`, `ssh`): an install passed that way is not blocked (L4, D2; the hook's
   threat model, the owner's ruling after plan pass 4).
   Test: none, out of the tripwire's reach by design; L4 states the bound
2. A hand commit made through `bash -c`, `eval` or a script in a Builder pane is not seen by the commit guard (the same
   gap `git-safety.sh` states for its other checks).
   Test: none, the hook reads command text only
3. An answer whose tag the Builder never prints (it read the answer but quoted none of it) reads as not acknowledged and
   main is told after 600 s: a false alarm, never a lost answer.
   Test: answer-worker.test.sh "an answer to a mid-turn pane that is never read ends NOT acknowledged (exit 1), after the queued line"
4. A launching pane Orca cannot place in a checkout leaves no `COMMANDECK_MAIN_PANE_DIR`, and a send then queues with
   the plain warning of C10.
   Test: to-main.test.sh "a queued send to main says main will not see it"

## 3. Assumptions (each settled, or a Builder check with the action per outcome)

- [verified] The guard blocks the issue 372 setup command when setup is named by a variable or a relative path, and passes it
  by an absolute path: the run in C1, 2026-10-26.
- [verified] `bash -c 'npm install lodash'` is blocked today (same run); C1 keeps it blocked.
- [verified] `fullSuiteBeforeFinal` from setup is added to `/config` only where it has none: `scripts/install-lib.sh:476`
  (`select($o[.key] == null or $o[.key] == "project")`).
- [verified] The round file's last line is the verdict: `scripts/builder-codex-pass.sh:1523` ends `"$BODY" "$VERDICT"; } > "$OUT"`.
- [verified] The Builder's passes run main's plugin scripts: `scripts/builder-launch.sh:289` (`{scripts}` ->
  `$PP_SCRIPTS_Q`).
- [verified] Nothing in the plugin reads `COMMANDECK_ALLOW_AGENT_GIT`: `rg -n COMMANDECK_ALLOW_AGENT_GIT` lists
  `scripts/builder-codex-pass.sh:1181,1183,1208` only.
- [verified] No saved `maxRounds` or `maxReviewRounds` on this machine (L2).
- [verified] `ageSec` is already in each units row: `hooks/units-sources.ts:91,140`.
- [likely] The session types `${CLAUDE_PLUGIN_ROOT}` literally, or a relative path, when it runs setup. Settled as not
  load-bearing: C1 judges quoted text as data whatever names the script, and its tests cover the variable, relative and
  absolute forms, so nothing in the plan depends on which form the session types.
- [uncertain] B2, before C4: `codexReviewerModel` and `planJudgeSolModel` profile values are Codex family ids the
  account resolves (`sol`, `astra`; `config/routing.json` names `sol`). Check: `setup.sh --questions begin` prints the
  "Codex model:" line on this machine. Found: keep main's values. Not found: main fills that row with the id the line
  printed.
- [uncertain] B3, before C10: which `builder-launch` test stubs `orca-ide terminal list`, and that `worktree-setup.sh`
  keeps an unknown `env` key on a rerun. Check: `rg -n 'terminal list' scripts/__tests__/builder-launch-*.test.sh`, and
  run `worktree-setup.sh <wt>` twice on a file holding the key. A stub found: add C10's checks there. None: add the stub
  to `scripts/__tests__/builder-launch-resume-launch-line.test.sh`'s fake `orca-ide`. Key dropped: write it after every
  `worktree-setup.sh` call in `builder-launch.sh` and name that in the evidence.
- [uncertain] B4, before C1: `python3 -I` is on PATH wherever the hook runs (`scripts/requirements.sh` lists python3
  for all profiles; the hook's manifest branch already calls it). Check: `grep -n python3 scripts/requirements.sh`.
  Listed: go on. Not listed: the reader's failure path (read whole) covers a missing python3, and the evidence says so.
- [uncertain] B5, before C6: whether `builder-codex-pass-class-sites.test.sh:33`'s fixture has a seat record with a
  handle. Check: read its fixture setup. With a handle: the check flips to a hand-off to that pane. Without: it stays a
  skip, with the new reason text.
- [uncertain] B6, before C8: whether a test asserts the "Classes not yet in the failure table" line. Check:
  `rg -n 'not yet in the failure table' scripts/__tests__`. Found: flip it to the new line. None: nothing to flip.

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| Two passes at once (timing) | a dead holder's lock; two passes of one worktree started together | one runs, the other is refused naming the live pid | builder-codex-pass.test.sh "two passes started together on a dead holder's lock: one runs and the other is refused" |
| Exit after a takeover (timing) | pass A running; its lock's pid replaced by a live pass B | A's exit leaves B's lock and pid | builder-codex-pass.test.sh "the first pass's exit leaves the second's lock in place" |
| Code inside quoted data (odd data) | `echo "$(npm install lodash)"`; a heredoc body's `$(npm install x)` | blocked both | dependency-addition-guard.test.sh "a real install still blocks: alone, after cd x &&, after ;, inside $(...), inside double-quoted $(...), inside backticks" |
| Answer never read (limit, cut off) | Builder mid-turn for the whole 600 s | NOT acknowledged, main told once | answer-worker.test.sh "in main's foreground an answer never read reaches main as one question" |
| Old install, new questions (old shape) | `.claude/commandeck.json` with no `blockAt`, `passCap`, `freshClosing` | `--questions begin` names the review workflow as not answered | setup.test.sh "an install with no review workflow answers is asked them" |
| Code given as text (odd data; the stated limit L4) | `bash <<< 'npm install lodash'` (r1); `echo bash -c "..."` (r1), `command echo bash -c '...'` (r3), `bash -o pipefail -c '...'` (r4); `if true; then bash -c '...'; fi` (r2); `bash -c '...'`, `sh -lc`, `eval '...'`, `sudo bash -c`, `bash <<'EOF'`, `cat <<'EOF' \| bash`, `cat <<'EOF' > >(sh)` | each passes: code handed to another program as text is data (D2, the owner's ruling after plan pass 4); `bash -c "$(npm install lodash)"` still blocks, the outer shell runs it | dependency-addition-guard.test.sh "code given as text is data, the guard's stated limit", "a shell name among a program's arguments is printed, not run", "a substitution in a shell's double-quoted -c text still blocks" |
| An earlier command beside a body (timing) | `bash -c true;` or `bash --version &&` before `cat <<'EOF'` with an install in the body (r2); the same on an earlier line (r1); none | each body is data, the same with the earlier command removed: the reader keeps no runner | dependency-addition-guard.test.sh "a body after '<cmd>' is data" |
| An unquoted body's substitutions (odd data) | `bash <<EOF` / `echo '$(npm install lodash)'` / `EOF` (r3); `cat <<EOF` / `$(npm install lodash)` / `EOF` | blocked: the outer shell expands an unquoted body first, quote marks inside it included; `cat <<'EOF'` with the same body passes | dependency-addition-guard.test.sh "an install inside a heredoc body's $(...) still blocks", "even inside single quotes in the body" |
| A git option with a value before the subcommand (odd data) | `git --attr-source HEAD commit -m x` in a Builder pane (r4 sweep) | refused like a plain commit: `--attr-source`'s value is skipped | git-safety.test.sh "a git --attr-source HEAD commit in a Builder pane is refused" |
| A substitution inside arithmetic (odd data) | `echo $(( $(npm install lodash) + 0 ))`; `cat <<EOF` / the same line / `EOF` (r4 known gap) | blocked both: a `$((...))` is opened, its `$(...)` is code; `cat <<'EOF'` with the same line passes | dependency-addition-guard.test.sh "a substitution inside arithmetic is code" |
| /config On under a project Off (old shape, two sources) | project `fullSuiteBeforeFinal=false`, `/config` true, setup with `--test-command ''` | setup saves off to /config, notes it; a project On under a /config Off needs no note | setup.test.sh "a project false under a /config On with no test command is set off, noted, and handed to /config as off" |
| A Claude judge on the Codex profile (limit, two sources) | `--profile claude-openai --recommended --option planJudgeSolAgent=claude` | `planJudgeSolModel=gpt-6.1-sol` is skipped and named, the reviewer's kept; no refusal | setup.test.sh "a Claude judge asked for on the Codex profile drops the Codex judge model, and keeps the reviewer's" |
| A spend figure (odd data; main answers 6, 8) | a cents, thousands or three-digit figure in a doc, a plan, a script, a merge message, the changelog; a two-digit sum in a plan or a message; the same in a dashboard fixture; a fixture line with a banned name beside the figure; a link named like a fixture; a shell or awk field, also before a point and three digits | the doc, plan, script, message and changelog fail; the fixture passes; the banned name and the link fail; the field passes | leak-test.test.sh "a spend figure in a doc fails" and the C14 cases after it |
| This run's address over a saved one (two sources; pass 5, not in the plan list) | /config `0.0.0.0:8791`; `--option dashboardBind=127.0.0.1 --option dashboardPort=9999`, or `--bind`/`--port` | the job is installed at `127.0.0.1:9999` and /config saves it; an empty `--bind`/`--port` leaves /config's | setup.test.sh "--option dashboardBind=127.0.0.1 --option dashboardPort=9999 over a saved 0.0.0.0:8791 is the address installed", "an explicit answer beats every saved field ...", "an empty --bind and --port are no answer" |
| A saved model the run's agent cannot run (old shape, two sources; pass 6, not in the plan list) | /config `gpt-6.1-sol` for both seat models; `--profile claude --recommended`; the reverse (saved `opus`, `--profile claude-openai`); an explicit model answer; no agent chosen | both go back to the default, each named; the explicit answer stays; with no agent chosen the preflight judges as before | setup.test.sh "--profile claude --recommended (the finding's run) ..." and the five `stale_models` cases beside it |
| A saved value against this run's answer, every key (two sources; main answer 9) | a saved commandeck.json, project record, machine record and /config with a value for every field; no answer, `--recommended`, explicit answers | saved stands with no answer; the profile beats saved; an explicit answer beats both, for every field and profile key | setup.test.sh "with no answer every saved value stands", "an explicit answer beats every saved field ...", "--recommended beats a saved value for every profile key", "an explicit --option after --recommended beats it for every profile key" |
| A first setup --plan (limit, no manifest yet) | a machine with no install manifest; `setup.sh --plan` | the plan prints to the end; a manifest that is not JSON still fails | profile-revoke.test.sh "a manifest that does not exist yet is no record (empty, exit 0)", "a manifest that is not JSON still fails" |
| A test that makes its own expected value (odd data) | the recommended profile without a pass cap | the profile test fails: expected values come from `config/recommended.json`, and every pair is saved by its own flag's handler | setup.test.sh "the profile names a pass cap" and "and every value passes the --option check" |

## Claims to falsify

1. The guard's only reason the absolute-path setup preview passes today is `own_setup`
   (`hooks/dependency-addition-guard.sh:80`).
2. After C1 no line of the hook calls `ran`, `own_setup`, `no_bodies` or `whole`, and nothing outside the hook did.
3. `pp_option fullSuiteBeforeFinal` reads `/config` before the project file (`scripts/paths.sh:1143`, :1152-1155).
4. `REVIEW_CAP`, the P2 test in `holds()`, `p2_count` and the P3 reader at :620 are the only places the review threshold
   is decided; `merge-unit-local.sh` decides nothing of it on its own.
5. `maxRounds` / `maxReviewRounds` have no reader beyond the table in C3 (`rg -n 'maxRounds|maxReviewRounds|max-rounds'`).
6. The relay has no model, effort or fast userConfig key.
7. `pp_seat_pane main` falls back to `COMMANDECK_MAIN_PANE_DIR` when no recorded handle is live
   (`scripts/paths.sh:996`), so a set variable alone delivers.
8. Nothing but `builder-fresh-round.sh:132` types `/model` into a pane.
9. A Builder pane's hooks see `COMMANDECK_BUILDER=1` (`hooks/read-range-guard.sh:9` depends on it today).
10. The no-revise path for a small plan judged by Sol alone is in place (`scripts/builder-launch.sh:183-194`).

## Recommended profile

`project` takes the role's routing default. The Builder writes `config/recommended.json` from this table. The last column holds the host's configured values (main answer 2); the committed profile carries the values only. A claude model is written as its family word (the manifest's allowed words), the host id in the citation.

| Option | Allowed values | Recommended |
|---|---|---|
| orchestratorModel | project, opus, sonnet, fable | `opus` (routing.json main-session: claude-opus-5-5) |
| orchestratorEffort | project, low, medium, high, xhigh, max | `medium` (routing.json main-session; main-settings.json effortLevel) |
| builderModel | project, opus, sonnet, fable | `sonnet` (routing.json builder: claude-sonnet-5-5) |
| builderEffort | project, low, medium, high, max | `high` (routing.json builder) |
| fixerEnabled | true, false | `true` (routing.json builder-fix exists) |
| fixerFirstModel | project, builder, opus, sonnet, fable | `builder` (routing.json builder-fix firstPass.model: null, the launched Builder model) |
| fixerFirstEffort | project, builder, low, medium, high, xhigh, max | `builder` (routing.json builder-fix firstPass.effort: null, the launched Builder effort) |
| fixerModel | project, opus, sonnet, fable | `opus` (routing.json builder-fix: claude-opus-5-5) |
| fixerEffort | project, low, medium, high, xhigh, max | `high` (routing.json builder-fix) |
| codexReviewerModel | project; on codex any Codex model id (families sol, astra); on claude opus, sonnet, fable | `gpt-6.1-sol` (routing.json sol-reviewer) |
| codexReviewerEffort | project, low, medium, high, xhigh, max | `medium` (routing.json sol-reviewer) |
| codexReviewerFast | true, false | `false` (routing.json sol-reviewer fast) |
| planAuthorEnabled | true, false | `true` (routing.json plan-author exists) |
| planAuthorModel | project, opus, sonnet, fable | `opus` (routing.json plan-author: claude-opus-5-5) |
| planAuthorEffort | project, low, medium, high, xhigh, max | `high` (routing.json plan-author) |
| planAuthorFast | true, false | `false` (no host value: routing.json plan-author has no fast field, the default tier) |
| planJudgeSolEnabled | true, false | `true` (routing.json plan-judge-sol exists) |
| planJudgeSolModel | project; on codex any Codex model id; on claude opus, sonnet, fable | `gpt-6.1-sol` (routing.json plan-judge-sol) |
| planJudgeSolEffort | project, low, medium, high, xhigh, max | `high` (routing.json plan-judge-sol) |
| planJudgeSolFast | true, false | `false` (routing.json plan-judge-sol fast) |
| planJudgeFableEnabled | true, false | `true` (routing.json plan-judge-fable exists) |
| planJudgeFableModel | project, opus, sonnet, fable | `fable` (routing.json plan-judge-fable: claude-fable-5-1) |
| planJudgeFableEffort | project, low, medium, high, xhigh, max | `high` (routing.json plan-judge-fable) |
| planJudgeFableFast | true, false | `false` (no host value: routing.json plan-judge-fable has no fast field, the default tier) |
| reviewBlockSeverity | P1, P2, P3 | `P2` (no host value: manifest default) |
| reviewPassCap | whole number >= 1 | `5` (no host value: manifest default) |
| freshClosingReviewer | true, false | `true` (no host value: manifest default) |
| closingPass | true, false | `true` (no host value: manifest default) |
| maxBuilders | whole number >= 1, or empty (no cap) | `` (no host value: manifest default, empty = no cap) |
| wakeKinds | comma list of worker_done, escalation, question, decision_gate, merge_ready, status, dispatch, handoff | `worker_done,escalation,question,decision_gate,merge_ready` (no host value: manifest default) |
| wakeWindowSeconds | whole number >= 0 | `60` (no host value: manifest default) |
| autoDecideSeats | chiefOfStaff, chiefOfStaff,main, off | `chiefOfStaff` (no host value: manifest default) |
| unitsBand | auto, on, off | `auto` (no host value: manifest default) |
| unitsPane | auto, on, off | `auto` (no host value: manifest default) |
| unitsStatus | auto, on, off | `auto` (no host value: manifest default) |
| mainPromptCacheTtl | 5m, 1h, leave | `1h` (main-settings.json env.CLAUDE_CODE_PROMPT_CACHE_TTL) |
| workerPromptCacheTtl | 5m, 1h, leave | `5m` (no host value: manifest default) |
| relayPromptCacheTtl | 5m, 1h, leave | `1h` (no host value: manifest default) |

## Not ordered (found, not planned)

- The host repo's twin of the new-package guard has the same false positive: port `bash_code` to it as one function
  (C1 keeps no plugin-only helper in its decision path so the port is a copy). Not done here.
- A relay model, effort or fast setting does not exist (D11); adding one is new work.
- `hooks/staged-index-warn.sh:32` warns on a quoted test word in the strict tier; harmless, not fixed.

## Version and CHANGELOG

C13. One entry, release-note style, the next free minor at merge time. Its lines say: setup offers a recommended set and
every value of every setting; the review workflow is three setup answers and the old round question is gone; an On for
the full suite is kept or refused plainly; the new-package guard no longer reads quoted text or note bodies as an
install; a Builder commits only through its pass; one pass holds a worktree's pass lock; fixer settings apply every fix
round; a Builder reaches a main in another checkout; an unread answer to a Builder is checked and main is told; a break
run is required before the first pass when the plan names one; small risky units get one plan judge; the failure table
is one row per save.

## Merge commit message

The squash message is written by `merge-unit-local.sh` (:397-400) from the batch brief's `Closes:` line, which carries
the `#` form (the batch is untracked; this plan writes "issue N", `ci/leak-words.txt`). It names Closes for issues 341,
351, 355, 362, 364, 368, 369, 371, 372, 373 and 374, and for issue 349 (the stall mechanic stays removed, closed with no code). Any issue the evidence marks partly built is named
Refs instead, with what is left, as the merge script already does.

## Files edited

`hooks/dependency-addition-guard.sh`, `hooks/__tests__/dependency-addition-guard.test.sh`, `hooks/git-safety.sh`,
`hooks/__tests__/git-safety.test.sh`, `scripts/setup.sh`, `scripts/__tests__/setup.test.sh`, `scripts/paths.sh`,
`scripts/builder-codex-pass.sh`, `scripts/__tests__/builder-codex-pass.test.sh`,
`scripts/__tests__/builder-codex-pass-threshold.test.sh`, `scripts/__tests__/builder-codex-pass-closing.test.sh`,
`scripts/__tests__/builder-codex-pass-fresh-round.test.sh`, `scripts/__tests__/builder-codex-pass-class-sites.test.sh`,
`scripts/__tests__/fixtures/builder-codex-pass-setup.sh`, `scripts/builder-launch.sh`,
`scripts/__tests__/builder-launch-resume-launch-line.test.sh`, `scripts/builder-fresh-round.sh`,
`scripts/__tests__/builder-fresh-round.test.sh`, `scripts/plan-tier.sh`, `scripts/__tests__/plan-tier.test.sh`,
`scripts/answer-worker.sh`, `scripts/__tests__/answer-worker.test.sh`, `scripts/to-main.sh`, `scripts/ask-main.sh`,
`scripts/__tests__/to-main.test.sh`, `scripts/__tests__/plugin.test.sh`, `scripts/__tests__/plugin-option.test.sh`,
`config/recommended.json` (new), `.claude-plugin/plugin.json`, `skills/setup/SKILL.md`, `templates/_builder-brief-template.md`,
`templates/_batch-brief-template.md`, `docs/setup-questions.md`, `docs/configuration.md`, `docs/review-loop.md`,
`docs/hooks.md`, `docs/troubleshooting.md`, `README.md`, `CHANGELOG.md`, `scripts/merge-unit-local.sh` (the comment at
:246-247), `ci/leak-words.txt`, `scripts/__tests__/leak-test.test.sh`, `hooks/units-sources.test.tsx` (C14), `ci/leak-test.sh`, `skills/worktreereview/SKILL.md`,
`.claude/plans/plugin-remainder-2026-10-25.md`, `.claude/plans/dashboard-parity-292-2026-10-23.md`,
`.claude/plans/commandeck-dashboard-seats-2026-10-17.md` (C14, main answer 6); for main answer 8 the rewording in
`docs/cost-control.md`, `docs/dashboard.md` and eleven older plans under `.claude/plans/` (beside files already listed);
for C15 `scripts/install-lib.sh`, `scripts/__tests__/profile-revoke.test.sh`, `scripts/__tests__/install-lib.test.sh`,
`scripts/__tests__/install-lib-setup.test.sh`. 65 files.

## 5. Build order and size (changed lines, code + tests + docs, estimates)

| Cut | Lines |
|---|---|
| C1 guard (issue 372) | 280 |
| C2 full suite (issue 374) | 45 |
| C3 review workflow (issue 373) | 230 |
| C0 issue 349 (no code) | 0 |
| C4 recommended set and groups (order) | 280 |
| C5 pass lock (issue 369) | 50 |
| C6 fixer every round (issue 355) | 85 |
| C7 Break gate, one judge (issue 362) | 85 |
| C8 failure table (issue 341) | 75 |
| C9 answer acknowledged (issue 351) | 60 |
| C10 main in another checkout (issue 368) | 55 |
| C11 commit guard (issue 371) | 35 |
| C14 public scrub (main answers 5, 6, 8) | 110 |
| C15 one setup precedence (main answers 7, 9) | 150 |
| C13 release | 35 |
| C0 issue 364 | 0 |
| Total | 1575 |

C2 before C3 and C4 (all three edit `setup.sh`'s answer flow; C2's `GIVEN` rule is what C3 and C4 save through). C3
before C4 (the profile holds C3's keys). C5 to C8 are sequential
edits of `builder-codex-pass.sh`. One unit regardless of size.

## Done when

- Every acceptance test named in C1 to C11 is green.
- `bash scripts/run-shell-tests.sh --changed main` is green.
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- `config/recommended.json` holds the values of the Recommended column.
- A closing (final) pass ends `VERDICT: GO` with no finding named.

## Main answers

1. Issue 349: the stall mark stays removed (the owner's 2026-10-25 order stands); C12 and the idle-minutes setting are dropped, the no-stall test stays, and issue 349 closes with no code.
2. Recommended profile: the last column holds the host's configured values (routing.json roles, main-settings.json), never code defaults; a key with no host counterpart keeps the manifest default and says `no host value`.
3. (superseded by 4) shell-argument-code, third return: D2's fixed wrapper table with the fail-closed fallback.
4. The owner's ruling after plan pass 4 (NO-GO, shell-argument-code in passes 1, 3 and 4): C1 is cut to what issue
   372 asks. Quoted option values and heredoc bodies are data, not installs. The parser for code given as text goes
   (`bash -c`, wrapper commands, runner option operands, the wrapper table of answer 3); installs hidden that way are
   the stated limit L4: the guard is a tripwire, not a security boundary. Revise the plan, then build (D2, C1).
5. The owner's order of 2026-10-26, added to this unit: the public scrub no longer bans a build's unit name, an issue
   number or a commit hash; paths, people's names, ruling ids, spend figures and secrets stay banned. Every home of the
   rule follows (C14).
6. The owner's ruling after pass 5: an automatic spend-figure check in this unit. A dollar spend figure fails
   `ci/leak-test.sh`; the dashboard's made-up fixture costs pass by an exemption of those files, not a weaker pattern;
   leak-test cases show a figure in a doc or a plan failing and the fixtures passing (C14, L5).
7. Main, after pass 5 stopped at the cap: the review limit for this unit is raised to round 7, the spend check is built
   here, and pass 5's open finding (the dashboard address) is fixed in the same round with a test, not filed (C15).
8. Main, during pass 6: widen the spend check. A dollar sign and three or more digits fails anywhere; one or two digits
   fail in text (`.md`, `.txt`, `.json`, the changelog); the fixture exemption stays; the changelog is searched and its
   hits reworded, not exempted; tests for a three-digit sum in a doc, a two-digit sum in a plan, a changelog figure
   (fail) and shell fields in a script (pass). The stated limit on whole sums is dropped (C14).
9. Main, after pass 6 stopped at the cap: one last fix round. Pass 6's finding is fixed as a class with passes 5's: one
   precedence for every value setup saves (this run's explicit answer, then the profile or `--recommended`, then the
   saved value), applied to every saved key and tested per key, the sweep in the evidence. Pass 7 is the last pass; a
   NO-GO there with only P2 or P3 open is a cap stop and main files what is open (C15).
10. The owner's ruling after main answer 9, superseding it on one point: no further plan or design review. The plan is
    revised for passes 5 and 6 and main answer 8 (C14, C15), then the unit is built; pass 7 is the code review. A later
    setup finding is fixed in the code review loop, and the merge still refuses an open P2 or worse. No mutation or red
    proofs are written; the tests stay.
11. During pass 7: the spend check keeps failing a dollar sign and one or two digits in a doc's code example (no
    code-block exemption, as a figure can sit in backticks). The failure for such a hit says how to fix it (write `${1}`
    for a shell parameter, or spell the amount out), and the word list's header states the `${1}` convention (C14).
12. After pass 7's GO on the tree before answer 11: unreviewed code never merges. The cap is raised to 8 and pass 8 is
    the closing pass over answer 11's files; its GO goes to merge. C15's revoke exception is accepted as written: a
    revoke is the owner's no.

## Plan change log

(none yet: each accepted judge finding gets one line here before the Builder starts)

- Pass 2 (heredoc-runner-leak, second return; shell-command-position): D2 redesigned. A body's verdict is bound to its receiver and the later stages of its pipeline, stamped on the body, in place of a line-wide runner flag; the program word is read past reserved words. C1's heredoc bullet, the Data design and two What can go wrong rows follow it. Design reviewed alone (pass 3) before the code.
- Pass 3 (shell-argument-code, third return; heredoc-expansion-code): D2's program word is resolved through a fixed wrapper table (options with values, operands, `find -exec`), one per simple command, with the old any-later-word reading kept only as the fail-closed fallback for an option the table lacks; a shell's `-c` is read only among its own options. An unquoted body gets both reads: the outer expansion's substitutions, then the runner's split. C1's code-as-text bullet, the Data design and two What can go wrong rows follow. Design reviewed alone (pass 4) before the code.
- Pass 4 (shell-argument-code, returned three times: r1, r3, r4): the owner's ruling (main answer 4) cut C1 to the issue: D2 now reads only what bash runs; code given as text, heredoc and here-string bodies are data whoever receives them, the stated limit L4. The receiver stamp, the wrapper table and the shell option table proposed in passes 2 to 4 are dropped. Kept from the reviews: a `$((...))` is opened (Sol's known gap), an unquoted body's substitutions are code. The sweep's `--attr-source` gap in C11's git option loop is fixed. C14 adds main answer 5's scrub change. C1, L4, the Data design, Accepted failure mode 1 and the What can go wrong rows follow.
- Pass 5 (unapplied-setup-option, not in the plan list): C15 added with its What can go wrong row. Main answers 6 and 7
  add the spend check to C14 (L5, a What can go wrong row) and raise the cap to 7.
- Pass 6 (stale-model-on-profile-switch, not in the plan list): with pass 5's finding, one class. C15 becomes the one
  setup precedence (main answer 9) with four What can go wrong rows; main answer 8 widens C14's spend check and drops
  the stated limit on whole sums.
- Build: the order forbids new end-to-end tests of setup, so the setup and option tests exercise one function or rule on hand-written config (function extraction) in place of the whole-script runs the plan's test lines name.

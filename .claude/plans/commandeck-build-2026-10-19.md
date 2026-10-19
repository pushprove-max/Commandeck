# commandeck-build-2026-10-19 -- one plugin build for every open issue (191-214)

Order: the owner, 2026-10-19 06:43 ET: "now start the plugin build for all the plugin issues". One unit, one
Builder, no split. Scope: every issue open at that time, 191 to 212 (22). At 06:44 the owner added 213 and 214
(ruling r-20261019-064404), so there are 24. Issues 191 to 202 and 205 already shipped (item 0); this build is
the other eleven. Issues 212 and 206 (both P1) are built first.

Base: local main 6c0e3dc (0.19.0, not yet pushed; origin/main is f7ac166).

Public repo: no personal names, handles, pane names (other than the existing seat directory name
`Chief-of-Staff`) or user paths in any shipped file, comment, test, commit message or changelog line. Outside
CHANGELOG.md an issue number is written "issue N". "The host project" is the project this plugin was taken
from. Its issue numbers are written "host issue N". Commit titles are plain.

Skill for the build: `mattpocock-skills:tdd`. Every item with logic is red first.

## Done when

- `bash scripts/run-shell-tests.sh` passes. It also passes once with jq 1.7 first on `PATH` (CONTRIBUTING.md).
- `dashboard-view.test.sh` runs, and is not skipped. Set `COMMANDECK_TEST_NODE_MODULES` to a node_modules folder
  that has jsdom; the brief names the folder. Item 9 changes the page, and without jsdom that file prints
  SKIPPED.
- `claude plugin validate .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh main` and
  `bash scripts/startup-size.sh` pass.
- No install, uninstall or whole-setup run, and no end-to-end test (owner ruling 2026-10-16). The tests drive
  functions and scripts on scratch HOMEs, as they do today.
- Every review pass runs through the pass script the brief names (the installed plugin's).
- Item 11 holds a worker's foreground waits to the cache life. The Builder's own test runs therefore go in the
  background with `wait-test-run.sh`, as the brief already says.

## Item 0. Close as shipped (main closes these; no build)

Each issue was checked against f7ac166 (0.18.0) and 6c0e3dc (0.19.0) at 6c0e3dc. Each "done when" is met.

| Issue | Shipped in | Evidence |
|---|---|---|
| 191 | f7ac166 | `scripts/builder-codex-pass.sh:114` (`CALLERS`) and `:116` (`LATER`); test `builder-codex-pass.test.sh:155` (r1 and r4 prompts carry both) |
| 192 | 0.16.0, confirmed in f7ac166 | `il_shadow_report`, `scripts/install-lib.sh:356`, called at `scripts/doctor.sh:114` and `scripts/setup.sh:595`. The issue's "risk on top" has no signal yet and is not built. |
| 193 | f7ac166 | `scripts/dashboard_alerts.jq:17` (every alert has an `Action:`), `:20` (`builder_warmup_input`), `:63`; test `dashboard-alerts.test.sh:27` and `:47` |
| 194 | f7ac166 | `scripts/cos-watch-inbox.sh:77` (`2>/dev/null` before `<`); test `cos-tell.test.sh:152` "with no owed mark, main's ended turn prints no shell error" |
| 195 | f7ac166 | `scripts/cos-watch-alerts.sh:29-55` (fingerprint, told again after 24 h); tests `cos-tell.test.sh:267`, `:271`, `:275` |
| 196 | f7ac166 | `scripts/to-main.sh:40-41` (`PROMPT_BLOCKED` screen read); `hooks/agent-startup-context.sh:116`; test `to-main.test.sh:158` |
| 197 | f7ac166 | `il_routing_merged`/`il_routing_seats`, `scripts/install-lib.sh:162`/`:204`; `scripts/setup.sh:257`, `:371`; `scripts/uninstall.sh:48`; tests `install-lib.test.sh:170-181` |
| 198 | f7ac166 | `scripts/main-watch.sh:409-416` (`wake-told` note to the relay); `scripts/cos-tell.sh:31-33` (`accepted:false`); `scripts/cos-watch-inbox.sh:144`, `:150`; tests `main-watch-helper-hold.test.sh:129`, `cos-tell.test.sh:62` |
| 199 | f7ac166 | `templates/main-session.md:20`; `hooks/agent-startup-context.sh:117`; test `agent-startup-context.test.sh:60` |
| 200 | f7ac166 | `hooks/cos-own-echo.sh`, registered at `hooks/hooks.json:15`; `hooks/__tests__/cos-own-echo.test.sh` |
| 201 | f7ac166 | `agents/lean-worker.md`, `agents/lean-checker.md`; `config/routing.json:119`; `hooks/agent-model-guard.sh:27-47` (routing's model and effort, the nudge); `scripts/subagent-usage.sh:27` (`--start`); `templates/_builder-brief-template.md:27`; tests `agent-model-guard.test.sh:81`, `plugin.test.sh:63`, `subagent-usage.test.sh:34`. See the note below this table. |
| 202 | f7ac166 | `scripts/seat.sh:70` (a plan seat's worktree is `<unit>`); `scripts/plan-worktree-close.sh:6-13` (`--adopt`); `scripts/builder-launch.sh:97`; tests `plan-worktree-close.test.sh:155`, `builder-launch-resume.test.sh` |
| 205 | 6c0e3dc | `INSTALL_LIB_TEST_CASE`, `scripts/__tests__/install-lib.test.sh:6`, `:11-12`; CHANGELOG 0.19.0. Close it after 6c0e3dc is pushed. |

Note on issue 201: `templates/test-audit.js:183` still calls the Workflow `agent()` with no agent type. The 0.18.0
plan allowed this: its batch auditors move to `commandeck:lean-checker` only if `agent()` takes an agent type.
Nothing in 201's "done when" depends on it. It is not built here (no issue asks for it).

Issue 203's wait cap shipped in 6c0e3dc (`scripts/wait-test-run.sh`, 270 s by default, exit 3 to wait again).
The rest of 203 is item 8.

## Item 1. Issue 212 (P1): no "merge it" after a NO-GO

**Root cause, read while planning:**

- The line main reads is `scripts/orca-wait.sh:336`, `next: merge it: bash .../merge-unit-local.sh <unit>`. It
  prints whenever `builder-codex-pass.sh --verify` passes (`:331`).
- The line above it (`:315`) prints the newest round's verdict, so main sees "last Codex round r5 (review)
  VERDICT: NO-GO" and then "next: merge it".
- `--verify` passes a NO-GO by design under the P2-tail rule (`scripts/builder-codex-pass.sh:26-30`, `:541-563`,
  `:615-675`). Under that rule a closing pass that ended NO-GO on P2/P3 findings only merges, and so does one
  narrowed pass after it. That rule is the owner's ruling of 2026-09-29 (host issue 2421).
- So a reviewer who rates a finding P2 (here, code that could wipe a customer's reply) is overruled by the next
  step. Also, a P0/P1 written in prose only, with no `[P1]` line, is not read (`:628`, a known `shortcut:`).

Issue 212 asks for two things. The next step after a NO-GO is never "merge". The merge refuses when the latest
verdict is not GO. The second would retire the P2-tail rule. The owner ruled on that (r-20261019-065159): **keep
the P2 tail at merge.** The script says "fix round" after any NO-GO and never "merge it". It names a P2-tail merge
as the owner's call, and main asks the owner before that merge. `--verify` does not change.

**Change, `scripts/orca-wait.sh` ~314-337:**

- Take the newest round file's last `VERDICT:` line. That is the pass's own verdict line (`:1095` writes it last).
- When it is `VERDICT: NO-GO`, print `next: fix round: r<N> ended NO-GO; the Builder fixes what it found and runs
  the next pass`, and never the merge command.
- When `--verify` also passes (the P2 tail), add one line: `the P2-tail rule lets this tip merge with its P2/P3
  open: merge only on the owner's word; ask them first`.
- The verdict is read from the round file, which the Builder can edit. That is acceptable here: this line only
  advises. The merge's own check is the gate.

**Change, `templates/main-session.md`, the injected rules:** one line: "A build whose last pass ended NO-GO merges
only on the owner's word, even when the merge check passes it under the P2-tail rule." Main's print is 9,803 of 10,240 bytes
today (`startup-size.sh`), so the line (about 150 bytes) fits. The Builder records the new number.

**Red first,** `scripts/__tests__/orca-wait.test.sh`:

- A unit worktree that holds its brief and an `r5-reports.md` ending `VERDICT: NO-GO`. A `status` message from
  that unit prints `next: fix round` and no `merge it`. Red today: the line does not exist.
- The same, where `--verify` passes. The test copies `scripts/` into its scratch folder, with a
  `builder-codex-pass.sh` stub there that exits 0 for `--verify`. The output has the owner's-word line and no
  `merge it`. Red today: it prints `next: merge it`.
- A unit whose newest round ends `VERDICT: GO` and passes `--verify` still prints `next: merge it`. This pins
  what is kept.
- `hooks/__tests__/agent-startup-context.test.sh`: main's print carries "merges only on the owner's word".

**Ponytail:** rung 5, one printed line and one rule line. Lazier option rejected: the rule line alone. The
script's own "merge it" is what main followed.

**Not built:** the prose-only P0/P1 the merge does not read (`:628`, an existing `shortcut:`). Issue 212 does not
name it.

**Size:** about 8 lines in orca-wait.sh, 1 template line, 30 test lines.

## Item 2. Issue 206 (P1): setup's own preview and apply are not blocked by the dependency guard

**Root cause, reproduced while planning** (the hook driven with a Bash payload, rc 2 = blocked):

| Command | rc |
|---|---|
| `bash <p>/scripts/setup.sh --profile claude --test-command 'npm test' --plan` | 0 |
| `... --test-command 'npm test' --auto-mode add --cache-ttl 5m --plan` | 2 |
| `... --test-command 'npm test' --global-claude merge --global-rules install --rules merge --plan` | 2 |

- `hooks/dependency-addition-guard.sh` `ran()` keeps quoted spans as data only on a line where every command is
  a "sender" (`SENDERS`: gh, orca, git commit, echo, ...).
- `bash setup.sh` is not one, so `whole()` reads the line with every quote mark erased. `npm test` and setup's
  own flags become one command: `npm test ... add --cache-ttl 5m`. That matches `NPM_LOOSE` (npm, any tokens,
  `add`, flags, a package-shaped word).
- Setup's answers `add` (`--auto-mode`) and `install` (`--global-*`) are common, so any project whose test
  command starts with npm is blocked.
- setup.sh never runs `--test-command` (it only saves it: `scripts/setup.sh:373`). Its one install, the
  add-ons (`:580`), comes from the plugin's own config, not from its arguments. So it is a sender of its quoted
  text.

**Change, `ran()`:** a segment also counts as a sender when its first word is `bash` or `sh` and its second word
is this plugin's own setup script. "Own" means the path resolves (`~` expanded, then `realpath`) to the same
file as `${BASH_SOURCE[0]%/*}/../scripts/setup.sh`. Then setup's quoted answers become `$QUOTED`. Every other
command on the line is still judged as code.

- The issue's other fix, "look only at the command actually run", is rejected for every command: it would miss
  `bash -c 'npm install x'`. The hook's header says to fail closed.
- A path the lexer cannot read (quoted with a space) falls back to `whole()`: a false block, never a miss.

**Red first,** `hooks/__tests__/dependency-addition-guard.test.sh`:

- Both blocked lines above pass, with the plugin's real `scripts/setup.sh` path.
- The same flags after `bash ./other/setup.sh` (not the plugin's) still block. This pins how narrow the change is.
- `bash <plugin>/scripts/setup.sh --test-command 'npm test' --plan && npm install lodash` still blocks.

**Ponytail:** rung 2, the existing senders rule and the house `strip_quoted` lexer. Lazier option rejected:
setting `COMMANDECK_DEP_APPROVED=1` in the setup skill. The issue rules that out: it approves packages.

**Size:** about 6 lines in the hook and 10 test lines.

## Item 3. Issue 204: a planning worktree's settings compare as JSON, not bytes

- **Cause:** `scripts/plan-worktree-close.sh:49` `setup_made` compares the worktree's
  `.claude/settings.local.json` with `worktree-setup.sh --print-settings` by `cmp -s`.
  - The 0.18.0 generator wrote the same keys in another order, so every planning worktree made before it is
    refused. Both the close and the Builder's `--adopt` (item 12 of 0.18.0) refuse.
- **Change:** `[ -s "$SETF" ] && a=$(jq -S . "$WT/$1" 2>/dev/null) && [ -n "$a" ] && [ "$a" = "$(jq -S .
  "$SETF")" ]`. A file that is not JSON still counts as the owner's.
- **Red first,** `scripts/__tests__/plan-worktree-close.test.sh`, beside the "settings plus a custom key" case
  (~86):
  - The printed settings with two top-level keys swapped: the close goes ahead.
  - The existing case, one changed value, is still refused.
- **Ponytail:** rung 3, `jq -S`, the issue's own fix. **Size:** 1 changed line and 6 test lines.

## Item 4. Issue 207: no notify question when the wrapper already calls the stable link

- **Cause:** `il_notify_repoint` (`scripts/install-lib.sh:521`) asks about every path that `il_notify_stale`
  (`:496`) finds. That path does not resolve to this version's hook.
  - A wrapper that calls the stable link `~/.commandeck/plugin/hooks/codex-notify.sh` is judged stale in a
    `--plan` run. Setup re-points that link only on apply (`scripts/setup.sh:394-395`), and the preview runs
    first.
  - The "new line" swaps the link for the same link, written as an absolute path. Old and new differ only in
    `~`, so the owner is asked about nothing.
- **Change, `il_notify_repoint` only:**
  - Drop from `s` each path that names `$IL_LINK/hooks/codex-notify.sh` once `~` is expanded. Setup re-points
    that link in this same run.
  - Return when `new` equals `old`.
  - `il_notify_stale` and the doctor's `il_notify_report` stay as they are. After a run the link resolves to
    this version, and the doctor says ok. A link left on an old version is still the doctor's warning.
- **Red first,** in `scripts/__tests__/install-lib.test.sh` (scratch HOME, `IL_PLAN=1`, `IL_LINK` pointing at
  an older folder):
  - A wrapper calling `~/.commandeck/plugin/hooks/codex-notify.sh`: no `ASK` line.
  - A wrapper calling an older versioned folder's hook: the `ASK` line, with old and new different.
- **Ponytail:** rung 2, a filter in the function that asks. **Size:** 3 changed lines and 12 test lines.

## Item 5. Issue 208: a marked block is replaced where it stands; an unchanged run writes nothing

**Root cause, reproduced while planning:**

- `il_block_text` (`scripts/install-lib.sh:551`) removes the block and appends the new one at the end of the
  file.
- `il_global` runs once per block (`scripts/setup.sh:438-439`). So with both blocks present, claude-md moves
  below rules, then rules moves below claude-md: the preview's "move up, move back down".
- Each removal leaves the blank line before it. Fed `my rules`, the claude-md block and the rules block, three
  runs went 147, 149, 151, 153 bytes, with the order the same and the blank lines piling up. This is the
  2-byte-per-run growth in the issue (9383, 9385, 9387).
- The backup: apply takes one, from the original. `il_backup` (`:589-595`) skips when that day's copy exists, so
  the issue's "possible problem" does not happen. The preview prints "would copy ... first" once per change,
  hence twice.

**Change, `scripts/install-lib.sh`:**

- `il_block_text` with a text file: when the file holds the block, print the text file in its place, and keep
  every other line as it is. When it does not, append as today. Taking a block out (no text file) is unchanged.
- `il_block` with a text file writes only when the result differs, as its no-text branch (`:548`) already does.
  This covers the AGENTS.md block (`setup.sh:413`).
- `il_backup` in plan mode prints its "would copy" line once per file per run: the file is noted in a variable.
- With these, a run whose blocks match writes nothing and takes no backup (`il_put`'s same-text return, `:559`).

**Red first,** `scripts/__tests__/install-lib.test.sh` (setup's two `il_global merge` calls, as setup makes
them):

- A global file of the owner's text and both current blocks: byte-identical after two runs, and the plan run
  prints no change and no "would copy".
- One block's template changed: that block is replaced where it stands, the other is untouched, the plan prints
  one "would copy", and the apply's backup holds the original bytes.
- The owner's text after the blocks stays after them.

**Prior art:** Ansible's `blockinfile` replaces a marked block in place, reports "ok" and writes nothing when
it is unchanged, and makes one backup per change.

**Ponytail:** rung 2, the same three functions. Lazier option rejected: stripping blank lines before append. It
would still move the blocks, and touch the owner's spacing.

**Size:** about 10 changed lines and 25 test lines.

## Item 6. Issue 209: the merge report counts the plugin's own earlier block

- **Cause:** `scripts/merge-rules.py:212` drops every commandeck block from an `--against` file before it counts.
  This is right for the merge: a rule only in setup's block is not the owner's, and counting it as theirs would
  take it out of the next block. The report then says "0 already in your files", and nothing says those rules
  are already in place.
- **Change:**
  - In the `--against` loop, also collect each rule found inside a commandeck block (`BLOCK.finditer`), as a
    second set.
  - The report's first line becomes `{n} plugin rules kept ({k} already in setup's block from an earlier run),
    {same} already in your files (left out), {mine} where you keep your own (left out)`.
  - It prints no `  already in ` line for them. `setup.sh:145` counts those lines, and the count must not
    change.
  - The merged text does not change. Leaving a matching block alone is item 5.
- **Red first,** `scripts/__tests__/merge-rules.test.sh`:
  - An `--against` file whose only rules sit inside a `commandeck:rules` block: the report says
    `(<n> already in setup's block from an earlier run)` and `0 already in your files`.
  - The text output still holds every one of those rules. This pins why they are not counted as the owner's.
- **Ponytail:** rung 2. **Size:** about 6 changed lines and 10 test lines.

## Item 7. Issue 210: a saved answer equal to the recommended one is one option

- **Cause:** `skills/setup/SKILL.md:21` marks a saved answer "(saved)", and "(recommended)" too "when it is that
  one". The saved voice `plain and brief` and the offered `Plain and brief` differ in case, so the model offered
  both.
- **Change:** that rule says the two are the same answer when equal ignoring case and surrounding spaces. Then
  one option carries both marks, and the saved text is what is sent.
- **Red first:** none. It is one line of skill prose, and no test reads the setup skill's rules. The review
  passes read it.
- **Ponytail:** rung 5. **Size:** 1 changed line.

## Item 8. Issue 203: helper caps and reuse, the repeat measure, the keep-warm ping, QUIET before the cache lapses

This ports the host project's tooling build of 2026-10-18/19 (host issues 2876, 2877, 2879), the parts its triage
marks for this plugin:

- O1, both parts: the reuse sentence, and the repeat measure in `unit-cost.sh`.
- O2: the answer-cap text only.
- O4: the keep-warm ping. The wait cap already shipped in 0.19.0.
- Cut 4 (QUIET at 225 s on 5-minute Builders): issue 203 ports it only if the owner approved it for the host
  project. The owner did, on 2026-10-19, and the host built it.

That triage also says the ping needs the background-job count first: the host's `pp_session_bg_open` (host
issue 2865), which this plugin never took. It is ported here as part 8c.

**8a. Caps and reuse (text):**

- `agents/helper.md`: "Answer by your 20th tool call with what you have. Anything you looked for and did not
  find is one line: `NOT FOUND: <what you searched, where>`." `maxTurns` stays 40: no one has measured this
  plugin's helpers.
- `templates/_builder-brief-template.md` ~30:
  - Every helper prompt, Explore included, carries the three caps: 15 lines, the 20th call, `NOT FOUND:`.
  - Add: "Before sending a helper, check whether an earlier helper this session already answered part of it,
    and put those `file:line` pointers in the new prompt instead of asking again."
- Red first, `scripts/__tests__/plugin.test.sh`: helper.md names `NOT FOUND:` and the 20th tool call, and the
  template names `NOT FOUND:` and the reuse sentence.

**8b. The measure, `scripts/unit-cost.sh`:**

- Per session line, `cold` and `coldK`: replies more than the session's own cache TTL after the one before, that
  wrote more cache than they read, and the tokens they wrote. TTL: any `ephemeral_1h_input_tokens` means 3600 s,
  else 300 s.
- After each session line, one helper line from `<session>/subagents/agent-*.jsonl`:
  - helpers, helpers over 20 tool calls, and final answers over 15 lines;
  - repeated searches, by the same Grep pattern, quoted `rg`/`grep` pattern, or Read path as an earlier helper
    of the same session.
- The TOTAL line sums both.
- Red first, new `scripts/__tests__/unit-cost.test.sh` (no test covers this script today), on a fixture session:
  - a 400 s gap whose reply writes more than it reads: `cold 1`; a 200 s gap: not cold;
  - two helpers sharing one `rg` pattern: `repeats 1`;
  - one helper with 21 tool calls: `over20 1`;
  - one 16-line answer: `over15 1`.

**8c. The ping and the earlier QUIET:**

- `scripts/paths.sh`, beside `pp_session_log_at` (~140):
  - `pp_session_bg_open <worktree>`: the background jobs the newest session record started
    (`toolUseResult.backgroundTaskId`) with no `<task-notification>` for them, or null.
  - `pp_session_cache <worktree>`: `{ttl, ctx, at, ended}` or null, from the last 400 lines of that record.
    Main-thread rows only. `ended` is true when the newest assistant or user row is an `end_turn` reply.
  - Both are the host's functions, unchanged.
- `scripts/dashboard_builders.jq` takes optional `bgOpen`, `cache` and `tick`:
  - QUIET is silent while `bgOpen > 0`. A Builder idle on its own background test run is waiting, not quiet.
  - QUIET's limit is `300 - tick - 15` when `cache.ttl == 300` and `tick` is given, else 300.
  - New signal `warm` when all hold:
    - `cache.ttl == 300`;
    - `cache.ended`;
    - `300 - tick - 15 <= now - cache.at < 300`;
    - something QUIET waits on is open (a background job, a live helper, or an open Codex pass);
    - `maxPings = floor(1.15*ctx / (0.1*ctx + 1.25*240 + 5*10)) > 0`.
  - Its `anchor` is the newest row only the parent can write: a `tool-start` with no `agent`, or a
    `subagent-request`.
  - The price constants are commented at the top.
- `scripts/dashboard.sh:311` passes `bgOpen`, so the dashboard shows no QUIET while a job runs. It passes no
  `cache` or `tick`, so the dashboard shows no warm signal.
- `scripts/main-watch.sh` `builder_watch` (~216-251):
  - `builder_card` passes all three.
  - The state gate becomes `working|done|idle`, with STUCK, QUIET and LOOP still acting on `working` only.
  - WARM types "Signal WARM: keep-alive while you wait. Reply with one . and end your turn."
  - WARM's history is its own file, `$hist.warm`: a ping never counts toward the third-episode post, and never
    posts to main.
  - One ping per `<since> <anchor>` window, at most `maxPings` per anchor.
  - QUIET's text names its limit in seconds.
- Template: "A `Signal WARM` line keeps your prompt cache alive while you wait: reply with one `.` and end the
  turn."

Red first, `scripts/__tests__/dashboard-built.test.sh` (it already runs the builders jq) and
`scripts/__tests__/main-watch-helper-hold.test.sh` (it already drives `builder_watch`), the host's cases:

- jq, with `tick 60` and cache `{ttl 300, ctx 100000, ended true}`:
  - idle 230 s with `bgOpen 1`: `warm`, `maxPings 11`;
  - idle 200 s, idle 310 s, `ttl 3600` at 3530 s, `bgOpen 0` with nothing open, `ended false`, and no `cache`:
    no warm;
  - ctx 1000: `maxPings 2`;
  - helper rows after the anchor do not move it;
  - QUIET at 226 s with a 5-minute cache, and not at 226 s without one;
  - no QUIET while `bgOpen 1`.
- `pp_session_cache` on fixture logs: a 5m write, a 1h write, no write (null), a skipped `isSidechain` row;
  `ended` true and false.
- main-watch:
  - a `working` Builder ending on `end_turn` with a job open gets one WARM per window, and none past `maxPings`;
  - `done` gets the first WARM too;
  - `waiting`, and a `tool_use`-ended log, get none;
  - no post to main;
  - after two WARMs, the first QUIET is still episode 1.

**Prior art:**

- A keepalive sent before an idle timeout, never after (TCP keepalive, long-poll intervals under a proxy's idle
  timeout), and only while it costs less than the expiry it saves.
- A deadline with best-effort partial results (answer by call 20).
- Anthropic's prompt caching documents the 5-minute and 1-hour cache lifetimes the TTL test reads.

**Ponytail:** rung 2, main-watch's existing tick and nudge path, the pure signal file, and the session-log
reader. Lazier option rejected: the wait cap alone. It shipped, and it covers 3 of the 12 rewrites the host
measured.

**Size:** about 12 lines in 8a, 60 in unit-cost.sh, 30 in paths.sh, 25 in the jq, 35 in main-watch.sh, 1 in
dashboard.sh, and 210 test lines. About 375 in all. This is the second-largest item.

## Item 9. Issue 211: the dashboard's phone view

- Port the host project's responsive page (host issue 2861, its "cut 3") into `dashboard/index.html`,
  `dashboard/app.css` and `dashboard/app.js`:
  - Under 760 px, a bottom tab bar: Units, Builds, Alerts, You, and More. Each shows only its own panels.
  - A More sheet lists the other panels and closes on Escape.
  - Step chips on the units board pick one stage.
  - Tab badges are counted from the same data as the summary tiles.
  - The page scrolls as a whole above a bottom pad, and the tab bar is fixed.
  - A dragged desktop panel height is ignored on a phone.
  - Panel links switch to the tab that holds the panel.
- Not ported: host panels this plugin does not have (deploys, PRs, issues, review), and the host's "cut 4"
  answer buttons. Issue 211 does not name them.
- **Already here:** `scripts/dashboard_serve.py` refuses a stale layout save with 409 and keeps cleared builds
  (`:19-25`, `:101`). No server change.
  - The page's side of the per-key layout merge (re-read `layout.js` on a 409, merge per key, then save again)
    is ported if `app.js` lacks it. The Builder checks this first; no 409 handling was found in `app.js`.
- **Red first,** `scripts/__tests__/dashboard-view.test.mjs` (jsdom), the host's cases adapted to this page's
  panels:
  - phone tabs show only their panels;
  - the More sheet lists the rest and closes on Escape;
  - a step chip leaves one stage;
  - a badge equals its tile's count;
  - a panel link switches tab;
  - a refused save re-reads and merges, keeping the other viewer's clear;
  - at desktop width no tab bar or chips show, and the existing cases stay green.
- **Layout, not seen by jsdom:** the Builder serves a fixture snapshot with `dashboard_serve.py` and takes
  headless screenshots at 390x844, 375x667 and 1280x800. Checks: no sideways overflow, the tab bar on the
  bottom edge, 44 px targets, and the desktop cards the same width before and after. The result goes in the
  evidence file. This runs no install and no setup.
- **Prior art:** CSS media queries and a bottom navigation bar (the iOS tab bar and Material bottom
  navigation). No framework is added: the page stays plain HTML, CSS and JS.
- **Ponytail:** rung 3, the same three files and one media query. The lazier option, a separate phone page, was
  ruled out by the owner for the host.
- **Size:** about 60 lines of CSS, 15 of HTML, 180 of JS and 150 test lines. About 405 in all, the largest item.

## Item 10. Issue 213: the batch-looks nudge reads commands with their quoted text set aside

This ports cut 1 of the host project's commit of 2026-10-19 (host issue 2884, plan `tooling-2026-10-19-review`).

- **Cause:** `hooks/batch-independent-looks.sh` `read_only()` (~91-115) checks the raw command.
  - It refuses any `>`, backtick or `$(` anywhere (`:103`), quoted or not.
  - It splits segments on `|`, `;` and `&` without regard to quotes (`:112`).
  - So `rg -n "foo|bar" a.ts | head` is not a look, and the nudge almost never fires. The host replayed 12
    sessions on its copy: 0 nudges for planners over 245 single-call turns before, 25 after.
- **Change, `read_only()`:**
  - Source `hooks/lib/strip-quoted.sh` beside `TOOL=` (~90), as `no-poll-loops.sh` and the dependency guard do.
  - Check backtick and `$(` on the raw command first: they run even inside double quotes.
  - If `strip_quoted` did not load, the call is not a look. Otherwise `CMD=$(strip_quoted "$CMD")`. That is one
    left-to-right pass, which drops quoted spans, comments and here-document bodies and never swallows a command
    that runs.
  - Then drop `2>/dev/null` and `2>&1`, and refuse any `>` left.
  - Per segment: drop a leading `do `, and allow `echo`, `printf`, `done` and a `for <name> in` header. `git`
    gains `rev-parse` and `ls-files`. Add `gh (issue|pr) (view|list)`.
  - The allowlist comment (~84-88) states the quote rule in one line.
- **Red first,** a new `hooks/__tests__/batch-independent-looks.test.sh`. Today the hook has cases only in
  `hook-tier.test.sh`, and every hook has its own file. It drives three turns per case on a fresh session.
  Red today:
  - `rg -n "foo|bar" a.ts | head -5; echo ---; sed -n '1,5p' b.ts | rg '=>'`: the third turn nudges;
  - `for n in 1 2; do gh issue view $n; done`: the third nudges;
  - `git rev-parse HEAD; git ls-files templates`: the third nudges.

  Green today and after:
  - two looks, then `rg -n "a|b" f > out.txt`: quiet, and the next look is quiet (a real redirect resets);
  - two looks, then `echo "$(touch x)"`: quiet;
  - two looks, then `echo "'"; touch out.txt; echo "'"`: quiet, and the next look is quiet (a quote inside the
    other kind of quote never hides the command between).
- **Ponytail:** rung 2, the hook's own allowlist read through the house lexer. Lazier option rejected: a `sed`
  that strips quotes. The host's first try was one, and it erased the `touch` above.
- **Size:** about 12 lines in the hook and 35 test lines.

## Item 11. Issue 214: no worker call waits past the prompt cache

This ports cut 2 of the same host commit (host issue 2885). The host's third cut, a dashboard test's clock, is
not ported (the order excludes it).

- **Cause:**
  - `hooks/worker-ask-guard.sh:50` prints `orca-ide orchestration ask ... --timeout-ms 600000`, a 10-minute
    block, to every worker it stops. The host's planner copied the same text and blocked twice for 601 s.
  - `hooks/no-poll-loops.sh:128-134` lets a worker's foreground sleep loop through with advice only. The host's
    Builder ran such loops for up to 344 s.
  - Either way the next reply rewrites a 5-minute cache.
- **Change, `hooks/no-poll-loops.sh`, the worker branch (`:128-134`) and its prefilter (`:67`):**
  - The prefilter's case list gains `*timeout-ms*|*wait-test-run*`, so a worker call whose only wait is one of
    those reaches the branch. Main's later checks key on their own patterns, so main's results do not change.
  - A worker's `Monitor` call, or a Bash call with `run_in_background` true, exits 0. Both end the turn, and the
    exit wakes the pane.
  - A worker's foreground call has one budget, `LIMIT`. It is `wait-test-run.sh`'s default (270 s) under a
    5-minute or unset cache, and 540 s when `CLAUDE_CODE_PROMPT_CACHE_TTL` is `1h`. Setup writes that variable
    into each pane's settings (`scripts/worktree-setup.sh:101`, `:169`), so the budget follows the cache life
    setup chose. A one-line comment names `wait-test-run.sh` as the source of the number.
  - The call's stated waits in `BARE` (quoted spans and here-document bodies already gone) are summed:
    - every `--timeout-ms N` or `--timeout-ms=N`, in seconds rounded up;
    - every `sleep N` in command position, with `s`, `m` and `h` multiplied out;
    - every `wait-test-run.sh <pid> <out> [max]`: its `max`, else 270.
  - A sum over `LIMIT` is refused: "BLOCKED: this call can wait up to S s in all, past the prompt cache's life,
    so the next reply rewrites it. One wait per call, at most 270 s: an ask takes --timeout-ms 240000 and on a
    timeout reruns with --resume <message id>."
  - A foreground sleep loop (`sleep_loop`, `:100-126`) states no end, so it is refused, not advised: "BLOCKED: a
    sleep loop in a worker pane waits past the prompt cache. A background test run: wait-test-run.sh
    <runner-pid> <output-file> from the plugin scripts (ends by 270 s; exit 3 means wait again). Anything else:
    start it with Bash run_in_background and end the turn; its exit wakes you."
  - Main's path (everything after `:134`) is unchanged.
- **Change, `hooks/worker-ask-guard.sh:50`:** `--timeout-ms 240000`, so the plugin's own refusal never hands a
  worker a command this guard refuses.
- **Change, `templates/_builder-brief-template.md`:** in the wait paragraph, one sentence: "`orca-ide
  orchestration ask` takes `--timeout-ms 240000`, and is resumed with the message id it returns."
- **The header (`:14-19`)** says what a worker is held to.
- **Red first,** `hooks/__tests__/no-poll-loops.test.sh`. Add a linked-worktree fixture beside `TEST_REPO`: one
  empty commit and `git worktree add`, removed by the `trap`. A `run_wt` like `run_hook` `cd`s there with
  `CLAUDE_CODE_PROMPT_CACHE_TTL` set per case.

  Red today (all exit 0 now), each must exit 2:
  - `until grep -q passed out.txt; do sleep 3; done`, and `while kill -0 123; do sleep 5; done`;
  - `orca-ide orchestration ask --from t --question q --timeout-ms 600000`; the same with `--resume m1`; the
    same under `1h`;
  - two asks of `--timeout-ms 240000` in one call (480 s); `sleep 180; sleep 180`; `sleep 400`;
  - `bash scripts/wait-test-run.sh 1 a.out; bash scripts/wait-test-run.sh 2 b.out` (540 s);
  - `worker-ask-guard.sh`'s printed ask carries a `--timeout-ms` no larger than 240000 (`worker-ask-guard.test.sh`).

  Green today and after (exit 0):
  - an ask of `--timeout-ms 240000`; under `1h`, `--timeout-ms 540000`;
  - `sleep 20; orca-ide orchestration ask --from t --question q --timeout-ms 200000` (220 s);
  - `bash scripts/wait-test-run.sh 123 out.txt`; `sleep 20 && npm test`;
  - a background `until test -f x; do sleep 3; done`;
  - a here-document `cat > notes.md <<'EOF'` whose body is an ask of `--timeout-ms 600000`;
  - every existing main case (`TEST_REPO`), unchanged.
- **Known gaps, left open on purpose** (the issue lists them): durations written `500.`, `.5` or `1e3`, and
  `sleep 200 200`. A test pins none of them.
- **Ponytail:** rung 2, the existing poll hook and `wait-test-run.sh`'s limit. No new hook and no new setting.
  Lazier option rejected: changing the printed `600000` alone. Orca's own dispatch text also prints 600000, and
  this plugin cannot edit it.
- **Size:** about 30 lines in no-poll-loops.sh, 1 in worker-ask-guard.sh, 1 template line, and 50 test lines.

## Version

- `.claude-plugin/plugin.json`: `0.19.0` to `0.20.0` (new behaviour: the second part, per `ci/version-check.sh`).
- `README.md:4`, the badge's URL and alt text. `plugin.test.sh:33` holds both to the manifest.
- `CHANGELOG.md`: `## 0.20.0 -- <date>` on top, one bullet per item 1 to 11, each with its `#N`. It also says:
  - issues 191-202 and 205 shipped in 0.18.0 and 0.19.0;
  - QUIET comes at 225 s for Builders on the 5-minute cache;
  - a worker's foreground sleep loop is now refused, not advised.
- About 22 changed lines.

## Order of work: each shared file is touched once

| Step | Items | Files |
|---|---|---|
| 1 | 1 | orca-wait.sh and its test; main-session.md; agent-startup-context.test.sh |
| 2 | 2 | dependency-addition-guard.sh and its test |
| 3 | 3 | plan-worktree-close.sh and its test |
| 4 | 4 + 5 | install-lib.sh (`il_notify_repoint`; `il_block_text`, `il_block`, `il_backup`), install-lib.test.sh |
| 5 | 6, 7 | merge-rules.py and its test; skills/setup/SKILL.md |
| 6 | 10, 11 | batch-independent-looks.sh and its new test; no-poll-loops.sh, worker-ask-guard.sh and their tests |
| 7 | 8 + 11's template line | helper.md, `_builder-brief-template.md` (item 8's lines and item 11's ask sentence, one edit), plugin.test.sh; unit-cost.sh and its new test; paths.sh, dashboard_builders.jq, dashboard.sh, main-watch.sh and their tests |
| 8 | 9 | dashboard/index.html, app.css, app.js, dashboard-view.test.mjs |
| 9 | version | plugin.json, README badge, CHANGELOG; the whole Done-when list |

- **Same file, more than one item:**
  - `_builder-brief-template.md`: items 8 (~30, helper caps and reuse; the WARM sentence) and 11 (the wait
    paragraph, the ask timeout).
  - `install-lib.sh` and `install-lib.test.sh`: items 4 and 5, in different functions. Re-run one case with
    `INSTALL_LIB_TEST_CASE=<text>` (0.19.0).
  - `hooks/lib/strip-quoted.sh` is read by items 2, 10 and 11, and changed by none.
  - No other file is shared.
- **Same data:**
  - Item 8's `bgOpen` changes when QUIET fires. QUIET posts and `stage-` alerts are not affected:
    `dashboard_alerts.jq` reads Builder signals by kind, and `warm` is not passed from `dashboard.sh`. The
    `builder-<p>/<u>-<kind>` alert ids do not change.
  - Items 8 and 11 both act on the 5-minute cache. Item 11 holds a foreground call to 270 s. Item 8 pings a
    Builder that ended its turn to wait. They never meet: a pane blocked inside a call has a `tool_use` reply
    newest, so WARM skips it.

## Size

About 1,060 changed lines, close to twice the 0.18.0 build (about 560). Items 8 and 9 are about three quarters of
it.

| Item | Lines |
|---|---|
| 9, issue 211 (phone view, tests) | 405 |
| 8, issue 203 (caps, measure, ping, tests) | 375 |
| 11, issue 214 | 82 |
| 10, issue 213 | 47 |
| 5, issue 208 | 35 |
| 1, issue 212 | 39 |
| 2, issue 206 | 16 |
| 6, issue 209 | 16 |
| 4, issue 207 | 15 |
| 3, issue 204 | 7 |
| 7, issue 210 | 1 |
| Version and CHANGELOG | 22 |

## Prior art

- **Item 1:** in common review gates, a blocking vote is never overridden by a later step without a person.
  Gerrit's -2 blocks submit, and GitHub's required reviews block a merge while changes are requested. The
  owner's P2-tail rule is a documented exception, and with this change a person decides each use of it.
  - No managed service gates a local `git merge` on a reviewer's session record. The plugin's own proof
    (`--verify`) stays.
- **Items 2 and 10:** POSIX shell quoting decides what is code and what is data. This is the same idea as
  shlex-style tokenising, with an allowlist of safe commands. The house `strip_quoted` lexer already does that,
  and command substitution is never read as data. No library is added.
- **Item 3:** JSON object members are unordered (RFC 8259). `jq -S` compares them as such.
- **Items 4-6:** idempotent config management, as Ansible's `blockinfile` and `lineinfile` do: a marked block is
  replaced in place, an unchanged run writes nothing and asks nothing, and one backup is kept per change.
- **Item 7:** none beyond the skill's own rule.
- **Item 8:** keepalive before the idle timeout, admitted by cost, and a deadline with partial results.
- **Item 9:** responsive CSS (media queries) and a bottom tab bar. No framework.
- **Item 11:** a client timeout below the idle expiry it must not cross, as long-poll intervals sit under a
  proxy's idle timeout. One budget per call (deadline propagation, as gRPC deadlines bound a whole call chain).
  Event-driven completion (background and wake) instead of polling.
- This repository has no `.claude/paved-road.md`. Nothing here adds a dependency, a service or a daemon.

## Not built

- Issue 192's "risk on top" (no signal yet), and moving `test-audit.js` to the lean checker (no issue asks).
- Retiring the P2-tail rule (issue 212, option A): the owner kept the rule.
- The merge not reading a P0/P1 stated only in prose (`builder-codex-pass.sh:628`, an existing `shortcut:`).
- The guard fix for plugin scripts other than setup.sh that take free text (`to-main.sh`, `cos-tell.sh`). No issue
  names them. They can false-block in the same way, and fail closed.
- The host's dashboard panels this plugin does not have, its answer buttons, and its dashboard test-clock fix.
- Issue 214's listed gaps: `500.`, `.5`, `1e3`, `sleep 200 200`.

PLAN-DONE

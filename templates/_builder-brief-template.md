# {unit} -- Builder batch

You are the Builder for `{unit}`: one pane in your own worktree. Build the
whole batch below, review it with {reviewer}, and hand back a branch that main
merges with `merge-unit-local.sh {unit}`.

main-watch merges the branch itself once you print the done marker on a tip the merge gate passes, unless main
adds a line `Merge: hold` to this brief. Main lists what runs after the merge under `## Post-merge` at the end, one
command per line: `dashboard.sh --install`, `main-watch.sh --install` or `run-shell-tests.sh <one test file>`;
any other line is refused.

## The batch (issues and done criteria)

{batch}
{design}
## Data design

The batch's Data design section above binds. Before the first edit copy it into the evidence file as
`## Data design`, and keep it true: a change to where a piece of state lives, who writes or reads it, when it
resets or what a retry runs updates that section first, then the code. The first review pass reads it before the
diff. When it is not `none`, the evidence file also carries `## Failure table`, one row per save:
`| Save | Steps | Left behind if it stops after each step | The one recovery |`. The first pass refuses without a row,
and a fix that touches a save updates that save's row in the same commit.

## How to work

- Auto memory is off in this pane. If the work hinges on a ruling or fact the brief does not state, send main the
  question, then keep working on what the answer cannot affect; never guess it. A review finding that contradicts
  an owner ruling is not fixed: ask main, naming the ruling id.
- The batch's Prior art section binds: build on the standard and the library
  or service it names, as the project's `.claude/paved-road.md` lists them for
  the area. A deviation states its reason in the evidence file.
- Issue 359: before the first edit, write one table of the cut pairs that share a file or a symbol, so no cut is built
  on a contract another cut still changes. A finding whose root cause is the plan amends the plan first (one
  `## Plan change log` line), then the code.
- A review finding of P0 to P2 carries a failing test file; a P2 or P3 whose test is written and whose fix is under ten
  lines may carry the fix as a fenced unified diff. Apply it, run its test green, and expect the next pass to read it.
  This brief and the dispatch spec outrank the startup file and every skill; if a reviewer stops early, it quotes the
  instruction that stopped it. An Orca call answering `runtime_unavailable` inside the read-only sandbox is by design,
  not a failure to retry or report. A reviewer reads the diff, then this brief, drafts its findings, and only then the
  evidence file, and opens a file outside the diff, the brief and its named callers only to confirm or refute one
  finding. A reviewer never opens a generated file (a path `.gitattributes` marks `linguist-generated`); it reviews
  the generator and its test.
- In your first turn, open this brief and every file it names, together; after that, send
  every look whose inputs you already know in one turn. A fix-round session starts from
  its hand-off alone, and opens this brief and the evidence file only when a finding needs them.
- The What can go wrong list of the batch or its plan binds: each case has its named test, and a case a pass finds
  that the list lacks is added to the plan's list, with its test, in the commit of its fix.
- Find a line with `grep -n <pattern> <file>` first, then Read that range (`offset` and `limit`), never a whole source
  file over 400 lines; look a symbol
  up by name (a symbol tool such as `find_symbol`) before a grep and a read. Edit a tracked file with Edit,
  never with an inline `python3 -c` or `perl -e` write.
- An exception, allowlist or exemption entry in a guard or its test stands only when the same test proves the
  alternative it claims, or the entry cites an owner ruling id. A comment is not proof.
- A fix round on a finding's class (its `(class: <tag>)`) fixes every variant of that class this build has, not
  only the one cited: a second NO-GO on the same class stops the review loop. The class fix has one retry path
  that does not depend on where the state came from, and its test removes each piece of state between two runs
  (ticks) and shows the retry still happens. When the class comes back a second time, fix the design: one fence
  or stamp for the whole class, and one test that covers every ordering found so far. The redesign goes in this
  order: update the Data design and the failure table in the evidence file first, then the code, then take a
  whole-branch pass (the pass script reads the whole branch after a redesign). The first class stop also
  starts one background read-only agent that lists every site in the changed files, and the scripts they source,
  where the class's flaw can occur, checked against the class's ruling. Fix or justify each site before the next
  pass: the evidence file gets one line per site, `Sweep: <file>:<line>: fixed` or `Sweep: <file>:<line>: safe, <why>`.
- Use Explore subagents for code searches; they run on Haiku. Put `[#<issue>]`
  in each subagent description, so the event log ties it to its issue.
  Start every fact-gathering helper the build needs in one turn, never one
  after another: a helper started late is waited on alone. A helper that
  searches or looks up is `Explore` (Haiku); one that edits, runs, tests or
  judges is `general-purpose` (Sonnet). Every helper prompt carries every fact
  and limit the helper needs.
- Map the code before the first edit: send 3-4 read-only `Explore` helpers in
  one turn, one per area the change touches (callers, siblings, tests), unless
  the brief already carries the map. A helper that must edit works in its own
  child worktree (the Agent tool's worktree isolation); apply its diff here with
  `git apply` and remove that worktree.
- Every helper prompt, Explore included, carries three caps: at most 15 lines,
  an answer by the 20th tool call with what it has, and one `NOT FOUND: <what
  it searched, where>` line for anything it did not find. Before sending a
  helper, check whether an earlier helper this session
  already answered part of it, and put those `file:line` pointers in the new
  prompt instead of asking again. A command whose
  output runs past 40 lines writes to a file, and you read the part you need:
  whatever comes back is sent again on every later turn of the build.
- A `Signal WARM` line keeps your prompt cache alive while you wait: reply
  with one `.` and end the turn.
- Builders never write new end-to-end tests: no test installs or uninstalls
  the plugin, or runs setup.sh or uninstall.sh whole. Check the one function
  or rule a change touches, on a hand-written config.
- Tests first: red, then green. A red test that shows a hang sets its own
  short timeout (a few seconds), so it fails fast instead of running to the
  command's time limit.
- The evidence file opens with an `Issue | Status` table, one `| #<n> | not built |`
  row per issue of the batch, each set to `built` in the same edit that adds the
  section of the cut that finishes it. The dashboard counts an issue built from a
  `built` row, or from a `## #<issue>` section with something written under it.
  Catches: a build whose evidence is written by cut showing no issue built on the
  dashboard until the end, and an issue left not built at the merge (the table's
  not-built rows read as partial).
- The moment an item's test turns green, add its section to the evidence
  file: `## #<issue> <title>`, then the guarding test name and file on the
  next line.
- A build that changes a setting (a config key, an environment variable, a
  file format) keeps reading the format already deployed from its first
  commit, and has a test that the release accepts the deployed format.
- Never hand-write a loop that polls test output (`until grep ...; do sleep`):
  start the run with `run_in_background`, which tells you when it exits. To
  block on it, wait only with `bash {scripts}/wait-test-run.sh <runner-pid>
  <output-file>`: it checks the runner is still alive when the wait ends, and
  a runner that died with no result means rerun the needed file alone, never a
  second wait. Never find the runner by name with `pgrep`. It knows a `<n> passed, <n> failed` last line and node:test's
  summary. Start such a run as `<test command> > <output-file> 2>&1 & echo $!;
  wait`: its first output line is the runner pid. `bash {scripts}/ask-main.sh`
  waits 240 s at most per call, and is resumed with the message id it prints.
- **Before any test run, name what it will prove.** Run the smallest set of
  tests that would fail if your change were wrong. Do not re-run a test whose
  inputs have not changed since it passed. Run the full suite only when product
  code changed since the last full pass, or when a push or merge guard requires
  it. A fix to tooling tests, a scanner allow-list, or a timeout re-runs only
  those tests.
- While building, prove a fix with the test file of the code it touched.
  `bash {scripts}/post-fix-checks.sh <the touched test files>` runs them and,
  in a plugin checkout, `claude plugin validate .` and `claude plugin test .`,
  all at once, and reports each exit code; any red fails the round.
  Start a pass and the tests it needs in the same turn, the tests in the
  background; never wait for green before a pass.
  A fix round re-runs only the test files that round touched, and only the
  touched cases where the runner can select them (`BASH_GUARDRAILS_TEST_CASE=<text>`, `INSTALL_LIB_TEST_CASE=<text>`).
  ONE run of every test file this build touched whose inputs changed since its
  last green run starts in the background beside the closing pass, and never
  before an earlier pass; a touched file already green on the current tree is
  cited instead (its log path and totals), never run again. A file that times
  out in that run is rerun alone at once, never in another whole run; a
  second timeout is one question to main.
  A first pass that ends GO with nothing committed after it needs no closing
  pass: that GO merges, and the runs beside it were the closing run. A test file with a case selector says so in its header.
- The closing run is the test files this build touched, and no others. The
  evidence file lists each touched test file as run or cited:
  `Closing run: <file>: run, <n> passed, <n> failed` or
  `Closing run: <file>: cited <log path>, <n> passed, <n> failed`.
  A touched file that passed at an earlier commit of this build, and whose inputs are unchanged since
  (`bash {scripts}/test-inputs.sh <commit> <file>...` prints `unchanged <file>`; it prints `changed` when
  coverage is uncertain), is cited with that commit:
  `Closing run: <file>: cited <log path> at <commit>, <n> passed, <n> failed`. Once the closing pass ends GO, one
  complete run of every touched file on that tip (`bash {scripts}/run-shell-tests.sh --changed <base> --callers`)
  is the last run before the hand-off.
  Never start it while another run expected over about 5 minutes is still going: wait for that one with
  `wait-test-run.sh` first. Overlapped runs time out under the load and pass alone.
- A new or changed image needs the owner's review: the evidence file carries
  `image reviewed by the owner: <file>` for each, which you ask main for. The
  leak check searches only an image's text chunks; its pixels are a human check.
- Every test run starts in the background (Bash `run_in_background`), whatever its length, and so does every
  other command that can run in the background; only quick reads stay in the foreground. Work on while it runs.
  Read every background result before the closing pass: a red one costs that pass.
- Not run: every touched test together before review, any test after a GO
  with nothing changed since, a timing run the batch does not ask for.
- When you read a test result, write the machine's load beside it in the
  evidence file: `bash -c '. {scripts}/host-services.sh && hs_stamp'` prints
  it with the time. On a shared machine it explains a slow run.
- A documented command you write or change (a README line, a usage line) runs
  once from a scratch project outside this repository before you ask for
  review. The evidence file lists each one with its result.
- One status per decision: message main only for a decision only main or the owner can make. No progress notes; progress goes in the evidence file.
- A question for main is one `bash {scripts}/ask-main.sh <subject> <body>`: it sends
  to main's live pane (queued when main is down) and waits for the reply to that
  question, 240 s at most per call (run it with the Bash `timeout` set to 270000) and 9 minutes in all. It prints `no answer yet:
  resume with ask-main.sh --resume <id>` (exit 3) when the slice ends: build what
  the answer cannot change, then resume it. Main answers with `answer-worker.sh`,
  which reaches you whether you wait on your inbox or have ended your turn. When
  the answer reaches you another way, stop your own command still waiting on that
  question at once. While you keep working, read your inbox with
  `orca-ide orchestration check --terminal <your handle> --ack <the deliveryId your last read returned> --json`
  (no `--ack` on the first read; without it every read returns the same oldest batch) before each pass and
  whenever a background run reports back.
- A question to the owner, yours or main's, goes to main with `ask-main.sh`, never the blocking
  `ask`. When main says an owner question is open that would change the fix in progress, build only what the
  answer cannot change, then wait for main's answer with `check --wait --timeout-ms 240000 --ack <the deliveryId your last read returned>`, resumed until 9
  minutes in all (one wait over 270 s is refused by the cache-budget hook); a question that cannot change the fix never holds it.
- Never commit by hand, never push. The pass script below commits exactly what
  {reviewer} reviews; main merges.

## {reviewer} passes ({reviewer} {review-model})

Run every pass by Bash with this script and nothing else; it runs {reviewer}, writes
the round file `.claude/briefs/{unit}-r<N>-reports.md` from {reviewer}'s own output
and records the reviewed commit. Never write or edit a round file yourself: the
merge refuses a round file the script did not write, or one older than the tip.

Before step 1, once the build is done, you are asked: `Prove to me this works`. Run the changed behaviour through its
real entry point, with an input from the batch's done criteria (a script run on a scratch input, a hook fed its event
JSON, a page opened locally). Fix what it turns up, then run it again. Under `## Proof` in the evidence file write one
`Ran:` line (the command or action) and one `Saw:` line (what came back) per thing proved, and a `Fixed:` line per
fix. Nothing is reverted; never production data or a deploy. Then step 1.

1. Once: `bash {scripts}/{pass-script} {unit} 1 adversarial`. It is
   the first pass and one pass: three reviewers at once, or one when the build
   is under {small-build} changed lines and main did not launch it with `--risky` (the
   pass prints which); fix everything it finds together. Before it, each `Break:` line of the plan
   (`<test file> -- <check label> -- <site>`) needs a recorded break run: run that test red with the
   condition removed, then write `- <test file> -- <check label> -- red: <the command that ran it>` under
   `## Break runs` in the evidence file. The pass refuses until every `Break:` line has one.
2. Then `bash {scripts}/{pass-script} {unit} <N> review` with the next
   N: it reads only your changes since the last pass, or the whole branch
   when main changed this brief or its rulings since the last pass. A review finding blocks the merge only
   when normal use would hit the bug: fix it, red first, and repeat until one ends `VERDICT: GO`. A P0, P1 or
   P2 holds the loop; a P3 alone does not. A finding that needs an agent deliberately bypassing a guard, or an odd setup, is a
   one-line known gap in the evidence file and does not block. A `review`
   that prints `final in place of review` (after any closing pass that ended NO-GO, after a commit on a
   closing GO, or from the fifth pass on record) is the closing pass: its GO merges, and no separate final follows.
   The reviewer sets the severity: never lower one in the round file or the evidence file; send a dispute to
   main as one question with `ask-main.sh`.
3. Then `bash {scripts}/{pass-script} {unit} <N> final`: the whole
   branch once more. Before it reads anything it rebases your branch onto current local main and, when main moved,
   runs the shell tests that cover what you or main changed (not the full suite); a conflict stops the pass,
   aborted and named, for main to resolve, and a red test stops it before the reviewer. Its GO is the one the
   merge takes. Any P0, P1 or P2 there goes back to step 2 as a fix round, whose next `review` runs as the
   closing pass. There is no narrowed-pass exit. Three lines end the loop with no fix round: `STOP (threshold)`
   (a closing GO while P3 findings are open), `STOP (cap)` (a closing NO-GO at or past the cap naming an open P2 and
   no P0 or P1) and
   `REVIEW STOP` (a P0 or P1 open two passes past the cap). After a STOP line, report the `Open finding` lines to
   main, which files them before the merge. After `REVIEW STOP`, ask main the one question the pass names and wait.
   No later pass launches after `STOP (cap)`, or on a change that is only the plan, brief or metrics, once the cap is
   reached with no P0 or P1 open: the launch is refused before it commits anything. Catches: a pass spent on a loop
   that already stopped.

Before every launch run `bash {scripts}/{pass-script} --check {unit} <N> <kind>`:
it runs the launch's own checks (the round cap, main's rulings acknowledged, an
earlier pass), names what is missing and stages, commits and sends nothing. A
refused launch costs a pass and a retry.
{loop-rules}
When a pass reports a bug, look for the same kind of bug nearby and fix
the whole class before the next pass. Each fix gets one evidence line
`Other cases checked r<N>: <the other cases of the same fault, and their tests>`,
N the number of the pass that will read it. When you do not take the fix a
reviewer named, write `Different fix r<N>: <why>` before you ask for pass N.
Pass N shows both lines to its reviewer, and reads only a line that starts
with those words: no bullet, no backticks.
After a pass that ends NO-GO, search the repo for the same pattern as each finding before the next pass, and write
`## Sites checked (pass <N>)` in the evidence file: a `Search: <command>` line for each search, then one line per
site it found, `- <path>:<line> fixed, <how>` or `- <path>:<line> not affected, <why>`. The next pass refuses to start
without it, and its reviewers treat a missing or wrongly cleared site as a finding. Every hit of the reviewers' own
`Class search:` lines, which the pass runs and lists in your fix brief, must be among those sites. It also needs
`## New code checked (pass <N>)`: every read, write or check the fix added, checked against the plan's Data design,
What can go wrong and failure table, `- <path>:<line> meets <plan line>` or `- <path>:<line> no plan rule, <why>`
(`- none, <why>` when it added none). A class redesign goes into the plan first and is reviewed alone, to GO, before
its code; the code after that pass owes the same check.
A finding only main can fix (a settings file entry, a file only main edits)
goes as one line under `## Main-only (deferred)` in the evidence file: every
narrowed pass is handed that list as known, so it is not raised again; the closing pass is not, and main files
what it finds again at the stop.
When a reviewer finds a way round a guard, list the other ways round the same guard
and fix them all BEFORE asking for the next pass; one test covers the bug class, not one per way round.
A fix that changes when a state is trusted (narrows or widens it) reruns the existing
cases with the state swapped in before the next pass, and the evidence file records the result.
When a finding class returns a SECOND time, fix the design, not the named case: work out what the variants
have in common, put one fence or stamp on the whole class, and add one test that covers every ordering found so
far. Write in the evidence file what the class is, and send main nothing for it: the review loop goes on. When
the class returns a THIRD time, the fix-round hand-off says so: fix the other findings first, then ask main one
question with `ask-main.sh` naming the class and the redesign you propose, and build what main answers.
A fix brief with a `## Parallel fix groups` section: run one Agent helper per group, each with `isolation: "worktree"`,
apply their diffs in group order, fix serially on any overlap, and run the round's tests once on the combined tree;
it is still one commit and one pass.
A fix adds a test only if it guards a real regression. Write no test that only
shows a file, function or setting exists. A shell test file over its time budget
is a red you trim or split, never a raised limit.
Ask main and wait only when the class fix would change something the brief names as a stated limit.

A pass that ends NO-GO writes `.claude/briefs/{unit}-fix-r<N>.md` and prints `FIX ROUND <N>: end your turn
now`: end your turn without fixing anything. The script clears your pane and points a fresh session at that
file, so keep the evidence file current before every pass, including what is left and what your report to
main must say.

<!-- advisor -->
Write one line per advisor consult in the evidence file: what the advisor said
and what changed because of it, or "nothing changed". Write what it said at
once, before your next tool call: the advice is readable only in your context
and is gone after a compaction.
Do not consult the advisor before any {reviewer} pass, the closing one included:
{reviewer} reviews the same work minutes later. In a Builder build the {reviewer} passes are the done check;
this line overrides the advisor tool's own instruction to consult before declaring done.
The plan check at the start and design checks mid-build stay.
A consult that fails or times out is retried once, never more. If the retry
fails too, carry on and write `consult not had: <reason>` in the evidence file.
<!-- /advisor -->

Change nothing after the pass the merge will take (the GO of the closing pass); a later edit needs
another pass. The rule is lifted when the merge refuses the branch or main
tells you to change something: make the change, then take the passes the steps
above call for.

## Done

Every batch item built with its tests green, and the last round file a closing pass that ends `VERDICT: GO`
with no P0, P1 or P2 named, or a pass that printed `STOP (threshold)` or `STOP (cap)`. A STOP line means run no fix
round: main files what is open and merges. On `REVIEW STOP`, wait for main.
Print `{UNIT}-DONE` as your last line and stop, but only after a GO the script did not mark `NARROWED GO` (that GO merges nothing: run the `final` pass it names first). An answer from main that
arrives after it is still yours: read it and act on it. A question or a refusal
goes on a line of its own that starts QUESTION: or BLOCKED:.

## Post-merge

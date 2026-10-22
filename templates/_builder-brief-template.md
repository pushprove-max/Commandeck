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
## How to work

- `/ponytail full`: the smallest complete change.
- Auto memory is off in this pane. If the work hinges on a ruling or fact the brief does not state, send main the
  question, then keep working on what the answer cannot affect; never guess it. A review finding that contradicts
  an owner ruling is not fixed: ask main, naming the ruling id.
- The batch's Prior art section binds: build on the standard and the library
  or service it names, as the project's `.claude/paved-road.md` lists them for
  the area. A deviation states its reason in the evidence file.
- In your first turn, open this brief and every file it names, together; after that, send
  every look whose inputs you already know in one turn. A fix-round session starts from
  its hand-off alone, and opens this brief and the evidence file only when a finding needs them.
- Find a line with `grep -n <pattern> <file>` first, then Read that range (`offset` and `limit`); look a symbol
  up by name (a symbol tool such as `find_symbol`) before a grep and a read. Edit a tracked file with Edit,
  never with an inline `python3 -c` or `perl -e` write.
- An exception, allowlist or exemption entry in a guard or its test stands only when the same test proves the
  alternative it claims, or the entry cites an owner ruling id. A comment is not proof.
- A fix round on a finding's class (its `(class: <tag>)`) fixes every variant of that class this build has, not
  only the one cited: a second NO-GO on the same class stops the review loop. The class fix has one retry path
  that does not depend on where the state came from, and its test removes each piece of state between two runs
  (ticks) and shows the retry still happens.
- Use Explore subagents for code searches; they run on Haiku. Put `[#<issue>]`
  in each subagent description, so the event log ties it to its issue.
  Start every fact-gathering helper the build needs in one turn, never one
  after another: a helper started late is waited on alone. A helper that
  searches or looks up is `Explore` (Haiku); one that edits, runs, tests or
  judges is `general-purpose` (Sonnet). Every helper prompt carries every fact
  and limit the helper needs.
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
- The moment an item's test turns green, add its section to the evidence
  file: `## #<issue> <title>`, then the guarding test name and file on the
  next line. The dashboard counts an item built only from that heading and line.
- A build that changes a setting (a config key, an environment variable, a
  file format) keeps reading the format already deployed from its first
  commit, and has a test that the release accepts the deployed format.
- Never hand-write a loop that polls test output (`until grep ...; do sleep`):
  start the run with `run_in_background`, which tells you when it exits. To
  block on it, wait only with `bash {scripts}/wait-test-run.sh <runner-pid>
  <output-file>`: it checks the runner is still alive when the wait ends, and
  a runner that died with no result means rerun the needed file alone, never a
  second wait. It knows a `<n> passed, <n> failed` last line and node:test's
  summary. Start such a run as `<test command> > <output-file> 2>&1 & echo $!;
  wait`: its first output line is the runner pid. `orca-ide orchestration ask`
  takes `--timeout-ms 240000`, and is resumed with the message id it returns.
- **Before any test run, name what it will prove.** Run the smallest set of
  tests that would fail if your change were wrong. Do not re-run a test whose
  inputs have not changed since it passed. Run the full suite only when product
  code changed since the last full pass, or when a push or merge guard requires
  it. A fix to tooling tests, a scanner allow-list, or a timeout re-runs only
  those tests.
- While building, prove a fix with the test file of the code it touched.
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
  Never start it while another run expected over about 5 minutes is still going: wait for that one with
  `wait-test-run.sh` first. Overlapped runs time out under the load and pass alone.
- A new or changed image needs the owner's review: the evidence file carries
  `image reviewed by the owner: <file>` for each, which you ask main for. The
  leak check searches only an image's text chunks; its pixels are a human check.
- A command expected to run over 60 seconds, a test or not, starts in the background
  (Bash `run_in_background`); work on while it runs. Read every background result before the closing pass:
  a red one costs that pass.
- Not run: every touched test together before review, any test after a GO
  with nothing changed since, a timing run the batch does not ask for.
- When you read a test result, write the machine's load beside it in the
  evidence file: `bash -c '. {scripts}/host-services.sh && hs_stamp'` prints
  it with the time. On a shared machine it explains a slow run.
- A documented command you write or change (a README line, a usage line) runs
  once from a scratch project outside this repository before you ask for
  review. The evidence file lists each one with its result.
- A question for main is one `orca-ide orchestration send --type question`.
  Main answers with `answer-worker.sh`, which reaches you whether you wait on
  your inbox or have ended your turn. When the answer reaches you another way,
  stop your own command still waiting on that question at once. While you keep working, read your inbox with
  `orca-ide orchestration check --terminal <your handle> --ack <the deliveryId your last read returned> --json`
  (no `--ack` on the first read; without it every read returns the same oldest batch) before each pass and
  whenever a background run reports back.
- A question to the owner, yours or main's, goes as `orchestration send --type question`, never the blocking
  `ask`. When main says an owner question is open that would change the fix in progress, build only what the
  answer cannot change, then wait for main's answer with `check --wait --timeout-ms 240000`, resumed until 9
  minutes in all (one wait over 270 s is refused by the cache-budget hook); a question that cannot change the fix never holds it.
- Never commit by hand, never push. The pass script below commits exactly what
  {reviewer} reviews; main merges.

## {reviewer} passes ({reviewer} {review-model})

Run every pass by Bash with this script and nothing else; it runs {reviewer}, writes
the round file `.claude/briefs/{unit}-r<N>-reports.md` from {reviewer}'s own output
and records the reviewed commit. Never write or edit a round file yourself: the
merge refuses a round file the script did not write, or one older than the tip.

1. Once: `bash {scripts}/{pass-script} {unit} 1 adversarial`. It is
   the first pass and one pass: three reviewers at once, or one when the build
   is under {small-build} changed lines and main did not launch it with `--risky` (the
   pass prints which); fix everything it finds together.
2. Then `bash {scripts}/{pass-script} {unit} <N> review` with the next
   N: it reads only your changes since the last pass, or the whole branch
   when main changed this brief or its rulings since the last pass. Every finding, P0 to P3, blocks the
   merge: fix it, red first, and repeat until one ends `VERDICT: GO` with no finding named. A `review`
   that prints `final in place of review` (after any closing pass that ended NO-GO, or after a commit on a
   closing GO) is the closing pass: its GO merges, and no separate final follows.
3. Then `bash {scripts}/{pass-script} {unit} <N> final`: the whole
   branch once more. Its GO, naming no finding, is the one the merge takes. Any finding there, P0 to P3,
   goes back to step 2 as a fix round, whose next `review` runs as the closing pass. There is no
   narrowed-pass exit and no finding left open at merge.

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
A finding only main can fix (a settings file entry, a file only main edits)
goes as one line under `## Main-only (deferred)` in the evidence file: every
later pass is handed that list as known, so it is not raised again.
When a reviewer finds a way round a guard, list the other ways round the same guard
and fix them all BEFORE asking for the next pass; one test covers the bug class, not one per way round.
A fix that changes when a state is trusted (narrows or widens it) reruns the existing
cases with the state swapped in before the next pass, and the evidence file records the result.
When a pass finds a SECOND variant of a finding you already fixed in this
build, fix the whole class, not the named case: work out what the variants have
in common, list every input the check trusts without verifying it, add one test
for the class (not one per variant), and write in the evidence file what the class is. Send
main a note of about 100 tokens (an Orca `status` naming the class and the fix)
without waiting for a reply. Ask main and wait
only when the class fix would cross a stated limit of this brief.
A fix adds a test only if it guards a real regression. Write no test that only
shows a file, function or setting exists. A shell test file over its time budget
is a red you trim or split, never a raised limit.

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
with no finding named.
Print `{UNIT}-DONE` as your last line and stop. An answer from main that
arrives after it is still yours: read it and act on it. A question or a refusal
goes on a line of its own that starts QUESTION: or BLOCKED:.

## Post-merge

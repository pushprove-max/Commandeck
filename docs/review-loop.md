# Review passes

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

A build's first pass reads the whole branch. It is three reviewers at once,
each leading with one angle and told all three, unless the commit is under 200 changed lines, or the number set at setup (insertions plus
deletions against `main`) and the build was not launched with `--risky`; then
it is one reviewer told all three angles. The pass prints which rule chose,
and the merge counts the lines again and refuses a one-reviewer first pass
the rule did not allow.

The first pass refuses to start until the evidence file shows its checks. Each `Break:` line of the plan (a test, a
check label and the site it guards) needs a line under `## Break runs`: the test run red with the condition removed,
and the command that ran it. A brief whose Data design is not `none` needs a `## Failure table` with a row per save
(steps, what is left after each, the one recovery). A plan with no `Break:` line and a Data design of `none` owe
neither.

After that come narrowed passes, each reading only the changes since the last
one, until one ends `VERDICT: GO`. A closing pass then reads the whole branch
again. If the first pass ends GO and nothing is committed after it, that GO
merges and no closing pass is needed. A project that answered "none" to the
closing pass at setup merges the narrowed pass that ends GO, once narrowed
passes have read every commit after the first pass.

The whole branch is `main...HEAD`, unless main launched the unit with
`builder-launch.sh --review-base <sha>`: then every whole-branch pass reads
`<sha>...HEAD`, so work already on main is read again. The sha must be a commit
on main; it is kept in main's `.claude/briefs/<unit>-review-base.md`. A
whole-branch pass whose range holds no change refuses before any reviewer
starts, and the merge refuses a GO whose range did not start at the unit's
base. With no closing pass, the first pass must have read from that base too.

A closing pass first rebases onto local main and runs the tests that cover
what changed. When setup recorded a typecheck command (`typecheckCommand`), it
must be green too: a red typecheck stops the pass before any reviewer runs and
names the command and its log; with none set, the pass says so and goes on.
The typecheck has a 300 s limit: a run past it stops the pass and names the
check that gave no result. A fresh worktree's typecheck cache is copied from a
sibling worktree when the project's typecheck keeps one, so its first run is
not cold.

Each pass after the first prints the files and lines changed since the last
pass, and says so when no code line changed (only comments or blank lines). If
main's brief or rulings for the build changed since the last pass, a `review`
pass reads the whole branch as a closing pass does, so a part main added in a
fix round is reviewed with the rest. The Builder's evidence-file lines
`Different fix r<N>: <why>` and `Other cases checked r<N>: <which>` go into the
prompt of pass N.

Each pass is checked against its saved prompt and its own reviewer session,
and earlier passes are checked too. Prompts are kept under the reviewer
home's `builder-pass-prompts/`. An update to the external Codex plugin's
prompt alone does not invalidate a saved pass. A missing prompt record, a
changed session prompt, or an incompatible change to this script's required
review text can still refuse it. Follow the refusal; a new unit reviewed
from pass 1 is the recovery it names.

Findings are graded P0 to P3. A review finding blocks the merge only when
normal use would hit the bug. A finding that needs an agent deliberately
bypassing a guard, or an odd setup, is a one-line known gap in the evidence
file and does not block: the reviewer lists it under `KNOWN GAPS:` with no
level or class tag, and a pass with only known gaps ends GO. A gap in
documentation, plan wording or a failure table is a P3 unless it hides a real
defect. A pass whose findings are all P3 ends GO.

Every pass reports placeholder UI as a P1 (class `placeholder-ui`): a control,
message or screen the change adds that is disabled for good, a stub, or says
it comes later, unless the plan or main's rulings name it on a
`Placeholder: <file> | <complete source line> | <why>` line. A plan or batch
line that describes placeholder UI is refused at launch unless it sits in a
fenced block, is a `Placeholder:` line, or cites the issue that tracks it.

A P0, P1 or P2 holds the loop (the blocking severity, P2 by default; set
`reviewBlockSeverity` to P1 so only a P0 or P1 holds, or to P3 so every
finding does; the setting is part of every prompt, so change it between builds, not during one): the Builder fixes it and the next `review`
runs as the closing pass. The pass count is the passes on record for the
build, not the number the Builder gives a pass. From the fifth pass on record
(the cap, `reviewPassCap`), `review` runs as the closing pass. The closing pass is handed the
plan's decisions and accepted failure modes, but no earlier finding (turn
`freshClosingReviewer` off and it is handed the review history like any pass). A fresh
closing pass reviews a detached copy of the pass commit with the unit's round reports,
hand-offs and evidence removed; the copy is deleted when the pass ends. The loop
stops at the first of these:

- A closing pass ends GO. Each P3 still open, its own or an earlier GO
  round's, is printed as an `Open finding` line (threshold stop).
- A closing pass at or past the cap ends NO-GO naming an open P2 and no P0
  or P1. Its P2 and P3 findings are printed as `Open finding` lines (cap
  stop). A NO-GO that names no P2 is no cap stop. After a cap stop no later
  pass launches, and past the cap none launches on a change that is only the
  plan, brief or metrics folders, while no P0 or P1 is open: the launch is
  refused before it commits anything.
- A P0 or P1 is still open two passes past the cap. The pass prints
  `REVIEW STOP` with a decision id, no fix round runs, and the next launch
  refuses until the owner answers that decision: the question the pass
  prints opens with the decision id, and its answered ledger row releases
  the stop. Only a pass whose every
  declared reviewer is on record, none naming a P0 or P1, clears an earlier
  P0 or P1; a pass with a reviewer missing clears nothing.

Before a merge with `Open finding` lines, main files one issue per class (the
`file.ext` the finding cites, or `no-file`), or comments the finding on an
open duplicate. Then it merges with `merge-unit-local.sh <unit> --filed
'<class>=#<n>' ...`. The merge refuses a class with no filing and an issue
GitHub does not report as open, and the squash commit names each filing. The
reviewer sets the severity: the Builder never lowers one, and sends a dispute
to main as a question. A finding main lists under
"Cleared findings" in its rulings file is handed to the next reviewer as out
of scope; it never turns a NO-GO into a merge.

The fix passes after a review run as the fixer role: the first on the Builder's
launch, every later one on Opus medium by default. The `fixer*` keys in `/plugin` config change both, and
`fixerEnabled=false` keeps every fix pass on the Builder's launch.

A launch with `--risky` opens the Builder at once. Its brief gets a
`## Risky launch` section, and its first pass has three reviewers whatever its
size. Setup adds no advisor, including for risky builds. A manually configured
`roles.builder.advisor` can still add one. A
launch with `--small` says the batch is expected under 200 changed lines; it
also drops an advisor written into `config/routing.json`'s `roles.builder` by
hand. A model override with a reason puts one launch on another allowed model.
For example:

```bash
bash "$PLUGIN/scripts/builder-launch.sh" --small --model sonnet --reason 'Small tooling change' add-csv-export .claude/briefs/add-csv-export-batch.md
```

To merge several finished units in order:

```bash
bash "$PLUGIN/scripts/merge-queue.sh" first-unit second-unit
```

The queue stops when a unit is refused or cleanup fails after its merge.

# Review passes

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

A build's first pass reads the whole branch. It is three reviewers at once,
one angle each, unless the commit is under 200 changed lines, or the number set at setup (insertions plus
deletions against `main`) and the build was not launched with `--risky`; then
it is one reviewer told all three angles. The pass prints which rule chose,
and the merge counts the lines again and refuses a one-reviewer first pass
the rule did not allow.

After that come narrowed passes, each reading only the changes since the last
one, until one ends `VERDICT: GO`. A closing pass then reads the whole branch
again. If the first pass ends GO and nothing is committed after it, that GO
merges and no closing pass is needed. A project that answered "none" to the
closing pass at setup merges the narrowed pass that ends GO, once narrowed
passes have read every commit after the first pass; one that set a round cap
has any pass numbered above it refused.

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

Findings are graded P0 to P3. A P0 or P1 refuses the merge. A closing pass
that leaves only P2 or P3 findings still merges: the merge prints each one as
open and files a GitHub issue for it. If GitHub cannot be reached the merge
stands, the output lists what was not filed, and the exit code is 4.

The fix passes after a review run as the fixer role. The first one runs on the
model and effort the Builder was launched with, and the later ones on Opus
high. The `fixer*` keys in `/plugin` config change both, and
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
It continues past issue-filing failures and returns 4 after the queue ends.

# Paved Road

The registry of what each area of this project builds on: the standards that
govern it and the library or managed service it uses. Copy this file to the
project's `.claude/paved-road.md` and add one row per area. Before
hand-building something, check its area's row. Building on something else, or
by hand where a row names a library or service, needs a stated reason in the
batch brief's Prior art section. A review finding against this registry cites
the row by area.

List a library or service only when the project already uses it or the owner
picked it. "None approved yet" means nobody has picked one: a build that needs
one asks main, it does not invent one.

The platform audit (`scripts/platform-audit/run-audit.sh` in the plugin) reads
both files as committed at HEAD, never an uncommitted edit, and gives each
area's auditor its Standards cell, by the Area id: two digits, a
dash and a lowercase name, for example `01-auth`. Each id also has one line in
`.claude/paved-road-areas.tsv`, tab-separated: the id, a one-line description,
and the paths the area covers, comma-separated. A path is a prefix (`src/auth`),
optionally followed by keywords in parentheses (`src/services (billing,
invoice)`: a file under the prefix whose rest names a keyword); a path with no
slash (`package.json`) also matches that name anywhere. Keep the ids in step,
one line per id. A change to this file or the areas file audits every area again.

| Area | Standards | Approved library or managed service |
|---|---|---|

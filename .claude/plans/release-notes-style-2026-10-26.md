Owner's words: the owner, 2026-10-26: every plugin release note is rewritten in the host product's production release-note style, and every future release follows it.

# Plan: release-notes-style-2026-10-26 -- every release note in the plain user-facing style, and a guard that keeps it

Tier: Standard
- Planned size: 12 files, 2890 changed lines

Launch: new unit release-notes-style-2026-10-26

LOCAL merge only, no push. Base: main `3730588` (0.48.0), 2026-10-26. Every file:line below was read on `3730588`.

Public repo: no personal names, seat nicknames, host product name, host paths, ruling ids or `#<3-4 digits>` issue
references in any shipped file, test, commit message or this plan (`ci/leak-words.txt`). Test fixtures that need an
issue reference use a one- or two-digit number (`#12`) and a made-up commit hash (`1a2b3c4d`).

Tests: changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`) plus `scripts/__tests__/help.test.sh`
by name (it runs every `scripts/*.sh --help`, and `--changed` does not select it for a new script). No red-proof run,
no `Mutation-verified:` line, no test-timeout raise. Tests run on the PC.

Timed checks: none. Neither `scripts/__tests__/release-notes.test.sh` nor `scripts/__tests__/update.test.sh` has a
time-bound check (`grep -n -E 'timeout|SECONDS|date \+%s|sleep'` on both: no match in either test body, 2026-10-26).
The heaviest new fixture, the guard over the whole CHANGELOG, took 0.02 s on today's 1762 lines (prototype, A4); the
whole file ran in 2.1 s today. It goes last in the file anyway.

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

1. Releases: 69 published releases and 69 CHANGELOG sections, one to one, no release without a section.
   Command: `diff <(gh release list --limit 200 --json tagName -q '.[].tagName' | sed 's/^v//' | sort -V)
   <(sed -n 's/^## \([^ ]*\) .*/\1/p' CHANGELOG.md | sort -V)`: no output, 2026-10-26. The rewrite script lists up to
   1000 releases (`gh release list --limit 1000`); more than that is out of scope.
2. Script names without an extension pass the guard: it knows a script or file name by its extension (the list in
   Decision D5). 1 tracked script under `scripts/` and `hooks/` has no extension
   (`git ls-files scripts hooks | grep -v __tests__ | grep -v -E '\.[a-z]+$' | wc -l` = 1, 2026-10-26).
3. An unbackticked two-part relative name with no extension (`scripts/foo`) passes, so `read/write` and `on/off`
   pass too. In today's CHANGELOG, 2 lines have such a name outside backticks and no other refusal, 2026-10-26: the
   lines this command prints, less the prototype guard's refused line numbers (A4):

   ```sh
   perl -ne '$t=$_; $t=~s/`[^`]*`//g; print "$.\n" if $t=~m{(?<![\w./-])[A-Za-z][\w.-]*/[\w.-]+}' CHANGELOG.md
   ```
4. A product name that ends in a listed extension (`Node.js`) is refused; the note writes `Node`. Today's CHANGELOG
   has 0 (`grep -c -i -E '\b(node|next|vue)\.js\b' CHANGELOG.md` = 0, 2026-10-26). A backticked `on/off` is refused
   as a path; written unbackticked it passes (limit 3).
5. The guard refuses the five banned kinds of the order only (a heading too deep for its place, a path or file
   name, a script or function name, an issue reference, a commit hash). Section order, intro paragraphs and wording
   are checked by the test over the real CHANGELOG (T13) and by review, not by the guard. 0 of today's 69 sections
   open with a `###` topic, 2026-10-26:
   `awk '/^## [0-9]+\.[0-9]+\.[0-9]+ -- / { v = 1; next } v && NF { if (/^### /) u++; v = 0 } END { print u + 0 }' CHANGELOG.md`
   prints 0. Today's CHANGELOG has 0 headings of three or more `#` (`grep -c -E '^#{3,}\s' CHANGELOG.md` = 0) and 0
   `##` lines that are not a version heading, 2026-10-26.

## Items (site, change, test)

1. CHANGELOG rewrite. Site: `CHANGELOG.md:3-1762`, all 69 version sections (0.1.0 to 0.48.0). Change: each section
   rewritten in the style below, version heading and date kept exactly. Today 582 of 1762 lines are refused by the
   guard (A4). Test: `release-notes.test.sh` "the whole CHANGELOG passes the style guard" (T12) and "every version
   section opens with a ### topic, and What you need to do comes first when there is one" (T13).
2. Republish. Site: new `scripts/release-rewrite.sh [--plan]`. Change: sets every published release's body to its
   rewritten section with `gh release edit <tag> --repo <owner/name> --notes-file -`, the repository bound from this
   checkout's `origin` (D9). Built and tested, NOT run by the Builder (Publish order below). Test:
   `release-notes.test.sh` T16-T20, T26-T28.
3. Style guard. Site: `scripts/release-notes.sh:2-11` (rewritten, ~35 lines). Change: the guard, a `--check [<file>]`
   mode, the version-heading split, and the body without its heading, its `###` topics promoted to `##`. Test:
   `release-notes.test.sh` T1-T11, T14, T15, T22, T23.
   Callers: `scripts/update.sh:27` (goes on after a refusal, stops on a missing section as today, Decision D4),
   `scripts/release-backfill.sh:20` (publishes nothing when a section is refused, Decision D10),
   `.github/workflows/release.yml:25` (the comment names the refusal), `release-notes.test.sh:2` (`# covers:` gains
   `CHANGELOG.md` and `scripts/release-rewrite.sh`, Decision D7). Test: `update.test.sh` T21, T24;
   `release-notes.test.sh` T25.
4. The rule in words. Sites: `CONTRIBUTING.md:17` (the changelog rule lives here; `docs/tests.md:56` points to it)
   gains the style in five lines and names `bash scripts/release-notes.sh --check`; `docs/tests.md:56` says the entry
   follows that style. No skill or template tells a Builder or plan to write a changelog line (Claim 2), so none is
   edited. Test: none, prose; the reviewer reads the two sites against the style below.
5. Version and entry. Sites: `.claude-plugin/plugin.json:3`, `README.md:4` (badge), one new CHANGELOG section in
   the new style. Test: `plugin.test.sh` "and the CHANGELOG's newest entry is that version" (existing, :35) and T12.

The style (from the order, the host's production notes): topic sections named for what a user does or sees, `###`
under the version's `## <x.y.z> -- <date>` in `CHANGELOG.md` and `##` in the published release body (D2), never
deeper; each bullet one or two plain sentences saying what changed for the person using the plugin, the effect first;
never file, script, function or path names, line counts, issue numbers or "Closes", commit hashes, internal unit
names, model or tool credits; a slash command, a setup question or a setting name the person types or sees is fine;
breaking changes and anything the user must do under `### What you need to do`, first; security fixes under
`### Security and maintenance`; no intro paragraph.

## Main answers

- Heading levels: `CHANGELOG.md` keeps `## <x.y.z> -- <date>` with `###` topics under it; the release body promotes
  them to `##`; the guard refuses `####` or deeper in a CHANGELOG version section and `###` in a release body; the
  extractor stops only at the next `## <x.y.z>` version heading (D2, D3, D5, T2, T3, T21-T23).
- Backfill: a version section the guard refuses is never published, not even with the "Version <x>." fallback; the
  guard runs on every body before any tag, push or `gh release` call, and the script exits 1 naming the version and
  line (D10, AF1, T25).
- Rewrite repository: the listing and every edit pass `--repo <owner/name>` from this checkout's `origin`;
  `GH_REPO` is unset for the gh calls (D9, T26, T27).
- Rewrite passes: pass 2 publishes the bodies pass 1 validated and kept; it does not run `release-notes.sh` again
  (D6, T28).
- Update: a missing section for the current version still fails `update.sh` as today; only a refusal goes on, so
  `release-notes.sh` exits 2 on a refusal and 1 on a missing section, and `update.sh:27` drops the blanket `|| true`
  for `|| [ $? -eq 2 ]` (D4, T21, T24).
- Test scope: the named `project-main.test.sh` run is removed (Done when 2).
- Rewrite origin: the `origin` URL must start with `https://github.com/`, `git@github.com:` or
  `ssh://git@github.com/` before the prefix is stripped and the `<owner>/<name>` check runs; any other URL (a relative
  path like `another/repo`, another host) exits 1 naming the URL before any gh call (D9, Break, T27).
- No red window: after every cut `bash scripts/run-shell-tests.sh --changed main` is green; the existing backfill
  rerun check gets its own clean CHANGELOG fixture and copies of both scripts, keeping its missing-section fallback
  case, and T12/T13 move to Cut 2 (AF1, Cut 1, Cut 2, Acceptance tests, Done when 2).
- Heading checks: Cut 2 compares `main`'s CHANGELOG version headings with the rewritten file's directly; only Cut 4's
  check, after the new entry exists, leaves that one entry out (Cut 2, Cut 4, Done when 4).
- T24's Break target is the `[ $? -eq 2 ]` predicate replaced with `true`; T21 covers removing the refusal handling
  (Break lines).
- Mutation lines: each line under Break lines starts `Mutation: `, not `Break: `, with its text kept; this unit runs
  no red proof, so the Builder records no break run, and reviewers check each named mutation against its test by
  reading it (Break lines).
- Leak-safe examples: D2's heading rule and D4's shell example carry no dollar sign followed by a digit; D2 names the
  sed back-reference in words, D4's function returns `"$rc"` (D2, D4).

## Decisions

D1. The guard lives in `scripts/release-notes.sh`. Every release body passes through it: the workflow's Notes step
(`.github/workflows/release.yml:30`, before Tag at :32-38 and Publish at :40-47), the backfill
(`scripts/release-backfill.sh:20`) and the update's display (`scripts/update.sh:27`); no other publisher exists
(Claim 3). A refusal in the Notes step fails the job before anything is tagged.
Test: `release-notes.test.sh` "the release Notes step fails on a section the guard refuses" (T14).

D2. In `CHANGELOG.md` version headings stay `## <x.y.z> -- <date>` and each version's topic sections are `###` under
it, so the file stays nested. The release body promotes each `###` topic to `##` (a sed
substitution of `^###(\s)` by `##` and back-reference one, that level only): the host style is one release per page. The extractor in `release-notes.sh` cuts a version's text from its
heading to the next `^## [0-9]+\.[0-9]+\.[0-9]+ -- ` only; today it stops at any `## ` (`release-notes.sh:9`), so a
stray `##` line inside a section would cut it short.
Test: `release-notes.test.sh` "the extractor keeps every topic of a version, up to the next version heading" (T2)
and "a ### topic in the CHANGELOG passes and comes out as ## in the release body" (T22).

D3. The release body is the lines under the version heading, without the heading and its leading blank lines, its
`###` topics promoted to `##` (D2). The host bodies open with their first `##` section; the release title and
`update.sh:26` already name the version.
Consumers: `release.yml:30`, `release-backfill.sh:20`, `update.sh:27`, `release-notes.test.sh:26-28` (updated).
Test: `release-notes.test.sh` "release-notes prints the newest version's section without its heading, the text
update.sh shows" (T1, replaces the check at :27-28).

D4. On a refusal `release-notes.sh <version>` still prints the body to stdout, writes each refusal to stderr as
`release-notes: CHANGELOG.md:<line>: <reason>: <text>` and exits 2; a missing section keeps today's exit 1 and
message (`release-notes.sh:10`). `update.sh:27` gains `|| [ $? -eq 2 ]`: the plugin updates from the marketplace's
main branch, not from releases, so a refused section must not stop a user's update, while a missing one still stops
it at :27 under `set -e` (`update.sh:13`), before any write, as today. Settled: under `set -e`, `f 2 || [ $? -eq 2 ]`
goes on and `f 1 || [ $? -eq 2 ]` exits 1 (`bash -c 'set -e; f() { rc=${1}; return "$rc"; }; f 2 || [ $? -eq 2 ]; echo after2;
f 1 || [ $? -eq 2 ]; echo after1'` printed `after2`, rc 1, 2026-10-26).
Test: `update.test.sh` "a version whose notes the guard refuses still updates, and the refusal is shown" (T21) and
"a version with no CHANGELOG section still stops the update, as it does today" (T24).

D5. The guard's rules, one perl program in `release-notes.sh` (prototype measured in A4). Each refused line is
named once per rule it breaks. The heading rules are two: `####` or deeper on a line of a CHANGELOG version section
(`--check` and `<version>` both run it), and `###` or deeper on a line of the promoted release body (`<version>`
only, after D2's promotion), named `release-notes: release body:<n>: <reason>: <text>`. Promotion turns `###`
alone into `##`, so the body rule fires only where a `####` or deeper heading was left in; `--check` reads the
CHANGELOG, where the `####` rule already refuses that line.

| rule | pattern (perl) | refuses | lets through |
|---|---|---|---|
| CHANGELOG heading | `^#{4,}\s` in a version section | `#### Details` | `### Joining a room` |
| release body heading | `^#{3,}\s` in the promoted body | `#### Details`, still `####` after promotion | `## Joining a room` |
| file or script name | `(?<![\w.-])[\w.-]*\w\.(sh\|py\|js\|mjs\|ts\|tsx\|jq\|md\|json\|jsonl\|tsv\|txt\|log\|yml\|yaml\|toml\|html\|css\|png)\b` | `release-notes.sh`, `scripts/x.sh` | `0.48.0`, `github.com` |
| backticked path | a backtick span whose first word is not a slash command (`^/[A-Za-z][\w:-]*(\s\|$)`) and that holds `\S/` or starts `/`, `~/`, `./` | `` `scripts/x` ``, `` `/usr/local/bin` ``, `` `~/.claude` `` | `` `/units band on` ``, `` `/plugin marketplace add owner/repo` `` |
| bare path | `(^\|\s)([~.]{0,2}/[\w.-]+/\|[\w.-]+/[\w.-]+/[\w.-])` | `~/.claude/settings`, `a/b/c` | `/units`, `read/write` |
| function name | `\b[A-Za-z_]\w*\(\)` | `fooBar()` | `fooBar`, `testCommand` |
| issue reference | `#\d+\b`, `\bCloses\b`, `\bRefs\b` (case-sensitive) | `#12`, `Closes 12`, `Refs 12` | "the pane now closes" |
| commit hash | 7-40 of `[0-9a-f]` with at least one digit and one letter, not beside `[\w-]` | `1a2b3c4d` | `1234567`, `defaced`, `2026-10-26` |

How a user-facing name is told apart: a slash command is `/` plus one name (letters, digits, `-`, `_`, `:`) and no
second `/` or extension, so `/units` passes and `scripts/x.sh` is refused by two rules. A setting name
(`testCommand`, `maxRounds`, `worker_done`) has no extension, no `/` and no `()`, so it passes; `fooBar()` is refused
only by its `()`. camelCase is never refused: the plugin's settings are camelCase (`docs/configuration.md`,
`.claude/commandeck.json` key `testCommand`). "Closes" and "Refs" are the squash's work-item words (commit `d1f61af`);
lower-case "closes" is plain English and passes.
Test: `release-notes.test.sh` T3-T9 and T23 (one refused case per rule) and "a clean section with a slash command,
setting names and plain words passes" (T10).

D6. Republishing is a new script, `scripts/release-rewrite.sh [--plan]`, not a backfill mode: the backfill walks
plugin.json's history and creates tags and releases; the rewrite walks the published releases and only edits bodies.
Pass 1 runs `release-notes.sh <version>` for every listed release, keeps each body in a bash array, and collects
every failure (no section, or a refusal); any failure prints `release-rewrite: v<x>: <reason>` for each and exits 1
with no release edited. Pass 2 runs `printf '%s\n' "${BODY[i]}" | gh release edit v<v> --repo "$REPO" --notes-file -`
per release, the body kept in pass 1, never `release-notes.sh` again, so a CHANGELOG changed between the passes
publishes nothing unchecked; it stops at the first failed edit. `--plan` prints `v<x> <body lines>` per release from
the kept bodies and edits nothing. No temp folder (so no raw `rm -rf`; `project-main.test.sh:91-92` lists the scripts
allowed one). A release with no CHANGELOG section: none today (limit 1); if one appears, pass 1 names it and nothing
is edited.
Test: `release-notes.test.sh` T16-T19 and "a CHANGELOG changed between the passes publishes the pass-1 bodies" (T28).

D7. `scripts/__tests__/release-notes.test.sh:2`'s `# covers:` line gains `CHANGELOG.md`, so
`run-shell-tests.sh --changed main` runs the guard over the whole CHANGELOG on every change to it
(`run-shell-tests.sh:92-95` matches each covers path exactly against `git diff --name-only`). Every plugin change adds
an entry (`CONTRIBUTING.md:17`), so a future unit meets the guard at its own merge check, not first at the release.
Test: `release-notes.test.sh` "its covers line names CHANGELOG.md, so a changelog change alone runs this file" (T15).

D8. The guard is perl: perl is a runtime requirement (`docs/requirements.md:9`, `scripts/requirements.sh:195`),
and the rules need look-behind and `\b`, which macOS and GNU awk and bash regexes do not share.
Test: none, a language choice; T3-T12 run it on both CI (Linux) and the PC (macOS).

D9. `release-rewrite.sh` binds its destination from `git -C "$ROOT" remote get-url origin`, two checks, both before
any gh call. First, the URL must start with one of `https://github.com/`, `git@github.com:` or
`ssh://git@github.com/`; any other URL (a relative path like `another/repo`, another host) exits 1 naming the URL.
Then `REPO` is the URL with that prefix and a trailing `.git` removed, and anything but `<owner>/<name>`
(`^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`) exits 1 naming the URL. Without the first check `another/repo` would pass the
second as it is. The script runs `unset GH_REPO` before its first gh call, and both `gh release list` and every
`gh release edit` pass `--repo "$REPO"`. Settled for this checkout: `git remote get-url origin | grep -c -E
'^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)'` printed 1, and the same URL through `sed -E
's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##' | grep -c -E
'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'` printed 1, 2026-10-26.
Test: `release-notes.test.sh` "with GH_REPO set to another repository, every gh call names this checkout's
repository" (T26) and "an origin that is not a GitHub repository stops the rewrite before any gh call" (T27).

D10. `release-backfill.sh` checks every body before it tags, pushes or calls `gh`. Pass 1 walks the same plugin.json
history and runs `release-notes.sh <v>` for each version: exit 0 keeps the body, exit 1 (no section) keeps today's
"Version <x>." fallback, exit 2 (refused) collects each stderr refusal as `release-backfill: v<x>: CHANGELOG.md:<line>:
<reason>: <text>`. Any refusal prints them all and exits 1 with nothing tagged, pushed or published, not even the
fallback. Pass 2 is today's loop body (`release-backfill.sh:15-20`) with `--notes` the body kept in pass 1. `--plan`
is unchanged (no gate; A2 uses it read-only).
Test: `release-notes.test.sh` "a backfill over a refused section publishes nothing, naming the version and line"
(T25).

## Accepted failure modes

AF1. `scripts/release-backfill.sh` publishes "Version <x>." only for a version with no CHANGELOG section (exit 1); a
refused section stops it before any publish (D10). Unchanged for the missing case: all 69 versions have a release
(limit 1), and the existing backfill rerun check at `release-notes.test.sh:73-77` keeps that fallback case: 0.2.1
has no section. Today it runs `$REAL/scripts/release-backfill.sh`, which reads the real CHANGELOG through
`release-notes.sh` (`ROOT` is the script's parent, `release-notes.sh:7`), and the real 0.1.0 and 0.2.0 sections have
refused lines (2 and 29 lines with a file name or issue reference, D5's extension and issue rules, 2026-10-26). In
Cut 1 the check gets its own fixture: `$T/b/scripts/` holds copies of `release-notes.sh` and `release-backfill.sh`,
and `$T/b/CHANGELOG.md` has clean `## 0.1.0` and `## 0.2.0` sections (one `###` topic, one plain bullet each) and no
0.2.1 section; the rerun runs `$T/b/scripts/release-backfill.sh`. So it is green after every cut.
Test: the existing check "a local tag whose push failed is pushed by the rerun before the release is made" passes
after every cut, on its own fixture; T25 covers the refusal.

AF2. The 69 published bodies stay in the old style until main runs `release-rewrite.sh` after the owner's leak check
(the order).
Test: none, a sequencing choice of the order; T16 proves the run.

AF3. A failed edit in pass 2 (network, rate limit) leaves the releases before it edited and the rest old. A rerun
edits all of them again to the same bodies.
Test: `release-notes.test.sh` "an edit that fails stops the rewrite there, exit 1, naming the release" (T20).

## Break lines

Mutation: scripts/__tests__/release-notes.test.sh -- a #### heading in a CHANGELOG section is refused, naming its line -- scripts/release-notes.sh guard CHANGELOG heading rule `^#{4,}\s`
Mutation: scripts/__tests__/release-notes.test.sh -- a release body with ### is refused -- scripts/release-notes.sh guard release body heading rule `^#{3,}\s`
Mutation: scripts/__tests__/release-notes.test.sh -- a file or script name is refused, naming its line -- scripts/release-notes.sh guard extension rule
Mutation: scripts/__tests__/release-notes.test.sh -- a backticked path is refused, naming its line -- scripts/release-notes.sh guard backtick-span rule
Mutation: scripts/__tests__/release-notes.test.sh -- an absolute or three-part path is refused, naming its line -- scripts/release-notes.sh guard bare-path rule
Mutation: scripts/__tests__/release-notes.test.sh -- a function name is refused, naming its line -- scripts/release-notes.sh guard `()` rule
Mutation: scripts/__tests__/release-notes.test.sh -- an issue reference is refused, naming its line -- scripts/release-notes.sh guard issue rule
Mutation: scripts/__tests__/release-notes.test.sh -- a commit hash is refused, naming its line -- scripts/release-notes.sh guard hash rule
Mutation: scripts/__tests__/release-notes.test.sh -- a release with no CHANGELOG section stops the rewrite before any edit, naming it -- scripts/release-rewrite.sh pass-1 gate before any `gh release edit`
Mutation: scripts/__tests__/release-notes.test.sh -- the release Notes step fails on a section the guard refuses -- scripts/release-notes.sh exit 2 on a refusal
Mutation: scripts/__tests__/release-notes.test.sh -- a backfill over a refused section publishes nothing, naming the version and line -- scripts/release-backfill.sh pass-1 gate before any tag, push or `gh` call
Mutation: scripts/__tests__/release-notes.test.sh -- with GH_REPO set to another repository, every gh call names this checkout's repository -- scripts/release-rewrite.sh `unset GH_REPO` and `--repo "$REPO"` on list and edit
Mutation: scripts/__tests__/release-notes.test.sh -- an origin that is not a GitHub repository stops the rewrite before any gh call -- scripts/release-rewrite.sh GitHub-prefix check on the origin URL (the `another/repo` and `https://example.com/x.git` cases)
Mutation: scripts/__tests__/release-notes.test.sh -- an origin that is not a GitHub repository stops the rewrite before any gh call -- scripts/release-rewrite.sh `<owner>/<name>` check on `REPO` (the `https://github.com/owner/name/extra.git` case)
Mutation: scripts/__tests__/release-notes.test.sh -- a CHANGELOG changed between the passes publishes the pass-1 bodies -- scripts/release-rewrite.sh pass 2 edits from the kept `BODY` array
Mutation: scripts/__tests__/update.test.sh -- a version with no CHANGELOG section still stops the update, as it does today -- scripts/update.sh:27 the `[ $? -eq 2 ]` predicate replaced with `true` (T21 catches removing the refusal handling)

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| odd data (allowed names) | a section with `` `/units band on` ``, `/units`, `` `testCommand` ``, `maxRounds`, `worker_done`, "read/write", "the pane now closes", `0.48.0`, `1234567`, a setup question in quotes | passes, exit 0, no stderr | release-notes.test.sh "a clean section with a slash command, setting names and plain words passes" |
| odd data (no section) | `gh release list` names v1.0.0 and v9.9.9; the fixture CHANGELOG has 1.0.0 only | exit 1, stderr names v9.9.9, no `gh release edit` call | release-notes.test.sh "a release with no CHANGELOG section stops the rewrite before any edit, naming it" |
| odd data (`###` topics) | version 1.1.0 with `### What you need to do`, a stray `## Notes` line and `### Security and maintenance`, then `## 1.0.0 -- <date>` | the body is every topic whole, `###` printed as `##`, no version heading, nothing from 1.0.0 | release-notes.test.sh "the extractor keeps every topic of a version, up to the next version heading" |
| limits (whole file) | the rewritten CHANGELOG, 69 sections plus this unit's | `release-notes.sh --check` exits 0 with no output | release-notes.test.sh "the whole CHANGELOG passes the style guard" |
| timing (update after a dirty merge) | the plugin's own version's section has a `#### Odd` heading; `update.sh` runs | the notes and the refusal print, setup and the doctor run, `update: done` | update.test.sh "a version whose notes the guard refuses still updates, and the refusal is shown" |

## Acceptance tests

`scripts/__tests__/release-notes.test.sh` (fixture tree `$T/p`, a git repository whose `origin` is
`https://github.com/owner/name.git`, holds copies of `release-notes.sh` and `release-rewrite.sh` and a fixture
`CHANGELOG.md`; a stub `gh` records each call as `GH_REPO=${GH_REPO-unset} <args>`, and `release edit` calls with their
stdin):

- T1 "release-notes prints the newest version's section without its heading, the text update.sh shows"
- T2 "the extractor keeps every topic of a version, up to the next version heading"
- T3 "a #### heading in a CHANGELOG section is refused, naming its line" (also: the body still prints, exit 2,
  refusal on stderr as `CHANGELOG.md:<line>`)
- T22 "a ### topic in the CHANGELOG passes and comes out as ## in the release body" (exit 0, no stderr)
- T23 "a release body with ### is refused" (a `#### Details` line: stderr names `release body:<n>` as well as
  T3's CHANGELOG line)
- T4 "a backticked path is refused, naming its line"
- T5 "a file or script name is refused, naming its line"
- T6 "an absolute or three-part path is refused, naming its line"
- T7 "a function name is refused, naming its line"
- T8 "an issue reference is refused, naming its line" (`#12`, `Closes 12`, `Refs 12`: three refusals)
- T9 "a commit hash is refused, naming its line"
- T10 "a clean section with a slash command, setting names and plain words passes"
- T11 "a version with no section exits 1 and says so" (existing check at :29-30, kept)
- T14 "the release Notes step fails on a section the guard refuses" (the step's `run:` via the file's `step` helper,
  in the fixture tree)
- T15 "its covers line names CHANGELOG.md, so a changelog change alone runs this file"
- T16 "release-rewrite edits every published release's body to its section"
- T17 "a release with no CHANGELOG section stops the rewrite before any edit, naming it"
- T18 "a release whose section the guard refuses stops the rewrite before any edit, naming its line"
- T19 "release-rewrite --plan lists each release and edits nothing"
- T20 "an edit that fails stops the rewrite there, exit 1, naming the release"
- T25 "a backfill over a refused section publishes nothing, naming the version and line" (a scratch repository
  `$T/bf` with copies of `release-notes.sh` and `release-backfill.sh` under `scripts/`, plugin.json commits 1.0.0
  then 1.1.0, a CHANGELOG whose 1.0.0 is clean and 1.1.0 has `#### Odd`, a bare `origin`, and its own recording `gh`:
  exit 1, stderr `release-backfill: v1.1.0: CHANGELOG.md:<line>`, 0 gh calls, 0 tags local or on origin)
- T26 "with GH_REPO set to another repository, every gh call names this checkout's repository" (`GH_REPO=another/repo`
  in the environment: every recorded call reads `GH_REPO=unset` and holds `--repo owner/name`, the list and each edit)
- T27 "an origin that is not a GitHub repository stops the rewrite before any gh call" (origin set in turn to
  `another/repo`, `https://example.com/x.git` and `https://github.com/owner/name/extra.git`: each exit 1, stderr
  names the URL, 0 gh calls)
- T28 "a CHANGELOG changed between the passes publishes the pass-1 bodies" (two releases; the stub `gh` rewrites a
  bullet of the fixture CHANGELOG on the first `release edit`: the second edit's stdin is the pass-1 body, unchanged)
- T12 "the whole CHANGELOG passes the style guard" (last in the file; added in Cut 2)
- T13 "every version section opens with a ### topic, and What you need to do comes first when there is one" (added
  in Cut 2)
- existing "a local tag whose push failed is pushed by the rerun before the release is made" (`:73-77`): moved onto
  its own fixture in Cut 1 (AF1), expected value unchanged

`scripts/__tests__/update.test.sh`: T21 "a version whose notes the guard refuses still updates, and the refusal is
shown" (the `$PL/CHANGELOG.md` link swapped for a fixture whose section for the manifest's version has `#### Odd`);
T24 "a version with no CHANGELOG section still stops the update, as it does today" (the link swapped for a fixture
with no section for that version: exit 1, stderr names the missing section, no `update: done`, the install manifest
unchanged).

`scripts/__tests__/help.test.sh` (existing, run by name): "release-rewrite.sh --help: exits 0, prints its usage,
calls nothing, writes nothing" and the same for `-h`.

## Assumptions (each settled, or a Builder check with the action per outcome)

A1. Settled: 69 releases, 69 sections, one to one (limit 1's command, no output, 2026-10-26).
A2. Builder check before Cut 2: `git fetch --tags origin && git tag | wc -l`. Today the checkout has 68 tags and
origin 69 (`git ls-remote --tags origin | grep -v '\^{}' | wc -l` = 69; v0.48.0 is missing locally). 69: read each
version's commits with `git log v<prev>..v<ver>` (`git log v0.1.0` for the first). Fewer than 69: take the commit
that set each version from `bash scripts/release-backfill.sh --plan` (read-only) and use that range.
A3. Settled: `gh release edit` reads the body from stdin with `--notes-file -` (`gh release edit --help`: "-F,
--notes-file file  Read release notes from file (use "-" to read from standard input)", 2026-10-26).
A4. Settled: the guard prototype (D5's rules) ran in 0.02 s over today's 1762-line CHANGELOG and refused 582 lines
(300 file or script names, 317 issue references, 135 backticked paths, 2 bare paths, 1 function name, 1 commit hash;
a line can break more than one rule); a clean sample of allowed names refused 0. The heading rules change no count:
today's file has 0 headings of three or more `#` (limit 5's grep). All 247 lines that
`bash ci/leak-test.sh --text CHANGELOG.md` flags today are issue references (`#<3-4 digits>`), which the guard
also refuses.
A5. Settled: a `# covers:` path is matched exactly against `git diff --name-only` (`run-shell-tests.sh:92-95`), so
`CHANGELOG.md` there selects the file.
A6. Builder check before Cut 4: `git fetch origin && git show origin/main:.claude-plugin/plugin.json | jq -r .version`
and the same for local `main`. Both 0.48.0: this unit is 0.49.0. Either higher: the next minor above the higher.
A7. Settled: `help.test.sh` runs every `scripts/*.sh` with `--help` and `-h` under a stub `gh` and fails a script that
calls it (`help.test.sh:16-27`): `release-rewrite.sh` answers `-h` before it lists anything.

## Claims to falsify

1. Every published release has a CHANGELOG section (limit 1's command prints nothing).
2. No skill or template tells a Builder or plan to write a changelog line: `rg -n -i changelog skills templates`
   prints only `skills/update/SKILL.md:16-17`, which shows the changelog on update.
3. `release-notes.sh` is the only source of a release body: `rg -n 'release (create|edit)|--notes' .github scripts
   hooks --glob '!**/__tests__/**'` prints only `release.yml:47` (its notes file comes from :30) and
   `release-backfill.sh:19-20`.
4. No consumer reads the version heading from `release-notes.sh`'s output: `release.yml:30` writes a body file,
   `release-backfill.sh:20` passes a body, `update.sh:26` prints the version before :27, and
   `release-notes.test.sh:28` is updated by T1.
5. `plugin.test.sh:35` still finds the newest version first: `grep -m1 -o '^## [^ ]* -- '` matches the top version
   heading; topics are `###`, which `^## ` does not match.

## Cuts (build order)

Cut 1, the guard. Files: `scripts/release-notes.sh`, `scripts/__tests__/release-notes.test.sh` (T1-T11, T14, T15,
T22, T23, T25 added; the existing rerun check at :73-77 moved onto its own fixture, AF1),
`scripts/update.sh:27`, `scripts/__tests__/update.test.sh` (T21, T24), `scripts/release-backfill.sh:10-21` (D10),
`.github/workflows/release.yml:25` (comment: "A missing changelog section, or one the style guard refuses, fails
the job here, before anything is tagged.").
Produces: `release-notes.sh <version>` = the body without its heading, `###` topics as `##`; exit 2 and stderr
refusals (CHANGELOG lines and release body lines) on a style break; exit 1 and today's message on a missing section;
`release-notes.sh --check [<file>]` = every refused line of the file (default the repo's CHANGELOG; the CHANGELOG
rules, not the body rule), exit 0 or 1. `release-backfill.sh` = exit 1 naming each refused version and line, nothing
published (D10).
Consumes: `CHANGELOG.md`. Existing consumers of the changed contract: `release.yml:30` (any non-zero fails the step,
unchanged), `release-backfill.sh:20` (changed, D10), `update.sh:27` (changed, D4), `release-notes.test.sh:26-30` and
`:75` (updated or unchanged); of the backfill: the owner, by hand, `release-notes.test.sh:66-70` (`--plan`,
unchanged) and `:71-77` (the rerun, on its own fixture, AF1).
After it, `bash scripts/run-shell-tests.sh --changed main` is green: `update.test.sh`'s existing runs read the real
CHANGELOG's 0.48.0 section, which the guard refuses (20 lines with a file name or issue reference, `awk '/^## / { n++
} n == 1' CHANGELOG.md | grep -c -E '\.(sh|md|json|mjs)\b|#[0-9]+'` = 20, 2026-10-26), so exit 2 goes on (D4), and
their checks grep single lines of the output (`update.test.sh:33-42`, `:74-82`), which the extra refusal lines do
not change.
About 48 + 88 + 2 + 11 + 12 + 1 changed lines.

Cut 2, the rewrite. Files: `CHANGELOG.md`, `scripts/__tests__/release-notes.test.sh` (T12, T13 added, green with
the rewritten file). Before it: A2. Per version, newest first: the old entry, and where it is
too terse to say what changed for a user, that version's commits; never a change that is in neither. The evidence
file lists, per version, its source (entry, or entry plus the commits read) and which bullets went under
`### Security and maintenance` or `### What you need to do`. After it, every version heading line is unchanged:
`diff <(git show main:CHANGELOG.md | grep -E '^## [0-9]+\.') <(grep -E '^## [0-9]+\.' CHANGELOG.md)` prints nothing
(no new entry exists yet). After it, `bash scripts/run-shell-tests.sh --changed main` is green (`CHANGELOG.md` in
the covers line selects `release-notes.test.sh`, D7).
Produces: `CHANGELOG.md` in the style. Consumes: `release-notes.sh --check` (Cut 1).
Existing consumers: `release-notes.sh`, `plugin.test.sh:35`, `update.sh` (through `release-notes.sh`),
`proof-run.sh:37` (copies the file, does not read it). About 1762 deleted and 900 added lines, and 8 test lines for
T12, T13.

Cut 3, the republish script. Files: `scripts/release-rewrite.sh`, `release-notes.test.sh` (T16-T20, T26-T28;
`# covers:` gains `scripts/release-rewrite.sh`). Before it: A1 re-run.
Produces: `release-rewrite.sh [--plan]` (D6, D9). Consumes: `release-notes.sh <version>` (Cut 1, any non-zero exit a
failure), `git remote get-url origin`, `gh release list --repo <owner/name> --limit 1000 --json tagName`,
`gh release edit <tag> --repo <owner/name> --notes-file -`. Existing consumers: none (new); main runs it.
After it, `bash scripts/run-shell-tests.sh --changed main` is green.
About 32 changed lines, and 16 test lines for T26-T28 (T16-T20 counted in Cut 1's 88).

Cut 4, the words and the version. Files: `CONTRIBUTING.md:17`, `docs/tests.md:56`, `.claude-plugin/plugin.json:3`,
`README.md:4`, `CHANGELOG.md` (the new entry, in the style). Before it: A6.
Produces: the written rule and the new version. Consumes: the guard's command name (Cut 1).
Existing consumers: `plugin.test.sh:31-35` (badge and newest entry), `ci/version-check.sh` (version moved).
After it, every version heading of `main` is unchanged, the one new entry left out:
`diff <(git show main:CHANGELOG.md | grep -E '^## [0-9]+\.') <(grep -E '^## [0-9]+\.' CHANGELOG.md | tail -n +2)`
prints nothing (the `tail` skips this unit's new entry, the newest heading). `bash scripts/run-shell-tests.sh
--changed main` is green.
About 6 + 2 + 1 + 1 changed lines, plus the entry inside Cut 2's estimate.

## Build order and size

| cut | files | changed lines (estimate) |
|---|---|---|
| 1 guard | 6 | 162 |
| 2 rewrite | 1 (+ the test file of Cut 1) | 2670 |
| 3 republish | 1 (+ the test file of Cut 1) | 48 |
| 4 words and version | 4 (+ CHANGELOG.md of Cut 2) | 10 |
| total | 12 | 2890 (the CHANGELOG is 92% of it, by the order's own scope) |

## Publish order (main, after the merge; the Builder runs none of it)

1. The owner's leak check of the rewritten `CHANGELOG.md`.
2. Then main runs, in the main checkout: `bash scripts/release-rewrite.sh --plan` (expect 69 lines, or 70 once
   0.49.0 is published), then `bash scripts/release-rewrite.sh`.
3. A push of the merge publishes 0.49.0's own body through `release.yml` and makes the CHANGELOG public, so main
   pushes only after step 1 too.

## Version and CHANGELOG

0.49.0 (new behaviour: the guard and the republish script), or the next free minor at merge (A6). One new section,
itself in the style, for example `### Release notes` (`## Release notes` in the release body) with two bullets: every past release note now reads as plain
notes about what changed for you; a release whose notes name internal files, scripts, issue numbers or commits now
stops before it is published and says which line to fix. The update keeps going when a version's notes break the
style, and shows why.

## Not ordered (found, not planned)

- Release titles are mixed: `Commandeck 0.47.0` and `v0.48.0` (`gh release list --limit 3`, 2026-10-26).
- `CHANGELOG.md` is exempt from the leak test (`ci/leak-test.sh:47`, `ci/leak-words.txt:5`). The rewrite will pass
  `bash ci/leak-test.sh --text CHANGELOG.md` (A4), which the Builder reports as input to the owner's leak check; the
  exemption itself stays.
- `config/retired.tsv:1` and `docs/commands.md:51` describe retired names as ones "the CHANGELOG retired"; after the
  rewrite the CHANGELOG no longer names most of them. The rows and the rules audit still work.
- `ci/version-check.sh:27` asks for a CHANGELOG entry without naming the style; `CONTRIBUTING.md` carries it.
- `README.md:321` only links the CHANGELOG; nothing in the README contradicts the style, so it is untouched.

## Done when

1. T1-T28 and the two `help.test.sh` checks for `release-rewrite.sh` are green.
2. `bash scripts/run-shell-tests.sh --changed main` is green after every cut (it selects `release-notes.test.sh`
   and `update.test.sh`), plus `bash scripts/run-shell-tests.sh scripts/__tests__/help.test.sh
   scripts/__tests__/plugin.test.sh`.
3. `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh`
   pass.
4. `bash scripts/release-notes.sh --check` exits 0 over the whole CHANGELOG; the Cut 4 heading diff prints nothing;
   `bash ci/leak-test.sh --text CHANGELOG.md` exits 0 (reported in the evidence file).
5. The Builder checks A2 and A6 are answered in the evidence file with their output, and the per-version source list
   of Cut 2 is there.
6. `release-rewrite.sh` was not run against GitHub (the stub `gh` only).
7. A closing (final) pass ends `VERDICT: GO` with no finding named.

## Question for the owner

None.

## Plan change log

- 2026-10-26, revision 0: first plan, read on `3730588`.
- 2026-10-26, revision 1: main's heading-level answer (Main answers): `###` topics in the CHANGELOG, `##` in the
  release body; D2, D3, D5's heading rows, the style, limit 5, A4, claim 5, the Break lines, T2, T3, T13, T21-T23,
  the What can go wrong rows, Cut 1 and the size follow it.
- 2026-10-26, revision 2: the plan judge's P1 backfill finding accepted: a refused section is never published, the
  gate runs before any tag, push or gh call (Main answers, D10, AF1, Item 3, Cut 1, Break, T25).
- 2026-10-26, revision 2: the plan judge's P1 rewrite-repository finding accepted: `--repo` from `origin`,
  `GH_REPO` unset (Main answers, D9, Item 2, Cut 3, Break, T26, T27).
- 2026-10-26, revision 2: the plan judge's P2 rewrite-passes finding accepted: pass 2 publishes the pass-1 bodies
  (Main answers, D6, Cut 3, Break, T28).
- 2026-10-26, revision 2: the plan judge's P2 update finding accepted: a missing section still fails `update.sh`;
  a refusal exits 2 and goes on (Main answers, D4, Item 3, Cut 1, Break, T3, T24).
- 2026-10-26, revision 2: the plan judge's P3 test-scope finding accepted: the named `project-main.test.sh` run is
  removed (Main answers, Done when 2).
- 2026-10-26, revision 3: the plan judge's P1 origin finding accepted: the origin URL must start with a supported
  GitHub prefix before the strip and the `<owner>/<name>` check; T27 adds `another/repo`, and
  `https://github.com/owner/name/extra.git` so the shape check keeps a case of its own (Main answers, D9, Break, T27,
  Cut 3).
- 2026-10-26, revision 3: the plan judge's P2 red-window finding accepted: the backfill rerun check gets its own
  clean fixture and script copies, T12/T13 move to Cut 2, every cut ends green (Main answers, AF1, Cut 1, Cut 2,
  Cut 3, Cut 4, Acceptance tests, the size, Done when 2).
- 2026-10-26, revision 3: the plan judge's P2 heading-check finding accepted: Cut 2 compares the headings directly,
  only Cut 4's check leaves out the new entry (Main answers, Cut 2, Cut 4, Done when 4).
- 2026-10-26, revision 3: the plan judge's P3 T24 Break finding accepted: the target is the `[ $? -eq 2 ]`
  predicate replaced with `true` (Main answers, Break lines).
- 2026-10-26, revision 4: the plan judge's P2 break-gate finding accepted: every `Break: ` line now starts
  `Mutation: `, text kept; no break run is recorded (Main answers, Break lines).
- 2026-10-26, revision 4: the plan judge's P2 leak-test finding accepted: D2 and D4 carry no dollar sign followed by
  a digit, meaning kept; D4's example reran with the same output (Main answers, D2, D4).

PLAN-DONE

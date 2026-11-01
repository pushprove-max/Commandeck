# commandeck-auto-setup-536 -- Auto Setup beside Custom in /commandeck:setup

Owner's words: the owner, 2026-11-01: build issue #536 (`gh issue view 536 -R pushprove-max/Commandeck`), Auto Setup (Claude + Codex, or Claude Only) beside Custom in `/commandeck:setup`. The issue body is the spec; read it first.
Owner's additions: the spec's binding decisions 1-5, 2026-11-01; decision 3's addition: no pinned model versions, Codex seats on the newest model the Codex CLI reports, and a test that fails on any pinned version; the four answers under `## Main answers`, 2026-11-01.
Goal: /commandeck:setup asks Auto Setup or Custom; Auto asks one question, applies the reference profile with detected values, merges and rewrites the owner's rules with backups uninstall restores.
Plan: .claude/plans/commandeck-auto-setup-536.md
Tier: Standard; LOCAL merge only; changed-file tests only during the build; tests run on the PC; no test-timeout raises.
Build order: C0, C1, C2, C3, C4.
- Planned size: 13 files, 860 changed lines
New tests: commandeck-auto-setup-536 25
Version: 0.67.0 (a minor: new behaviour), unless `bash ci/version-check.sh` at merge time names another free number.
Closes: #536
Timed checks: none -- every new case goes in a new file with no time-bound check; no heavy fixture is added to an existing file.
Helpers: every subagent call names its model: Sonnet `general-purpose` for code reading, test writing and mechanical edits; Haiku `Explore` for search. The Builder brief carries this line.
Test edits: scripts/__tests__/setup.test.sh:110 and :113 expect `sol` where they expect `gpt-6.1-sol` today (the owner's second answer); same checks, same counts, nothing weakened.

## Why

Custom asks 13 steps. Auto replaces every question but one with a profile file and code that detects the project's values, so the answers are data, not prose the skill re-reads. The one judgment step, merging and tightening the owner's rule text against the plugin's, stays with the model: it writes the merged text to a staging folder and setup.sh does every write, backup and record. The install manifest already keeps each file's prior bytes as a blob, so a new entry kind, rewrite, lets uninstall put a rewritten file back byte for byte, over an earlier Custom record too. The global CLAUDE.md serves every project, so the owner sees its change and says yes first. Model families only: Claude aliases and the Codex family `sol`, which the routing reader resolves to the newest model the account lists.

## Prior art

- Standard: none governs a setup wizard; the plugin's own install-manifest contract (install-lib.sh header) governs backups and restore.
- Library: Ansible blockinfile's marked-block pattern is already used (il_block_text); no library rewrites prose rules, so that step is the model's.
- Practice: dpkg conffiles (`.dpkg-old`) and oh-my-zsh (`.zshrc.pre-oh-my-zsh`) keep a copy for every change that replaces user bytes; D7's edited copy follows it.
- Built here: the manifest, its blobs and il_backup exist; this unit adds one entry kind and one staging check. scripts/proof-run.sh runs setup.sh for real on a temp HOME (:101); its override unsets and stubs (:29-52) are the D6 fixture's.

## Data design

- Auto profile: `config/auto-profile.json`, shipped, read-only: overrides of `config/recommended.json`, not a copy: `claude-openai` (the D3 overrides plus flags) and `claude` (D5's overrides on top). `--args` reads recommended.json's options, then the overrides, so a key added to recommended.json reaches Auto with no edit here. Written by no script.
- Rules staging folder: `$PP_SCRATCH/auto-rules/`, emptied by `auto-setup.sh --sources` at each Auto run, then written by the skill: one file per owner rule file it changes, named by its key (`CLAUDE.md`, `.claude/rules/<n>.md`, `AGENT_STARTUP.md`, `.claude/main-session.md`, `global/CLAUDE.md`), plus `conflicts.tsv` (`<key>\t<owner's line>\t<plugin rule>`). Read once by setup.sh; a refused run leaves it for the next try.
- Manifest entry: kind `rewrite`, `{prior, kind: "rewrite", written: "sha256:<staged text>"}`, the written text kept as a blob. At the manifest step, before any write of the run, il_rules_record records only the staged, non-empty files this run writes (`global/CLAUDE.md` only with `--global-rewrite yes`), as kind merge; a declined, unstaged or empty-staged file gets no record from it. il_rules_rewrite alone sets kind rewrite and `written`, together, so every rewrite entry has a `written`. An entry an earlier setup recorded (merge, from Custom) keeps its first `prior`; only kind and written change. Project files and their `.commandeck-bak` entries in the project manifest; `~/.claude/CLAUDE.md` and its `.commandeck-bak` entry in the machine's (IL_MACHINE), as il_global's il_put does. Reset: uninstall (il_restore) removes it.
- Backups: `<file>.commandeck-bak-<date>` (il_backup, unchanged), one per file per day. Edited copies: `<file>.commandeck-edited-<date>[-<n>]` (il_keep_edit, n the first free number), the owner's, in no manifest.
- Rewrite sequence (D7): at the manifest step (setup.sh:485), before any write: il_rules_check (D9), il_rules_record (staged, non-empty, written this run; kind merge; a first prior kept). Before il_global and il_own (setup.sh:620-627), per file: if that day's backup exists and the file differs from it and il_rules_same with the last `written` fails, il_keep_edit copies it first, named in the report; il_backup (the global file's into IL_MACHINE); kind rewrite and `written`, together; the staged text.
- Linked rule file: one whose realpath equals the realpath of AGENTS.md or of IL_GLOBAL, either link direction (CLAUDE.md -> AGENTS.md, AGENTS.md -> CLAUDE.md); il_rule_sources lists it as linked and Auto leaves it, so the Codex block setup writes through the link (setup.sh:582-583) stays.
- Edit test, il_rules_same <file> <written blob>, the one comparison D7 and D8 use: the file with its plugin blocks out (il_block_text with no text), then il_same against the blob, so the blank line il_block_text puts before a block (install-lib.sh:992) and trailing blank lines are no edit.
- Pinned-id scan (D6): both profiles by a real `setup.sh --auto <p>` run on a temp HOME and fixture project; then every regular file under the two is read for a pinned id, except `.git`, the seeded models cache and the 3 view files dashboard.sh copies whole into `~/.commandeck/dashboard/`, each skipped only while `cmp` equals the plugin's copy. setup.sh:477 preflights every run, so the fixture (A4) copies proof-run.sh:29-52 (its `unset` of every config-path override, then stubs: prompt template, HOST_OS Linux, `systemctl`, codex, claude, models cache, companion, an empty `~/Library/LaunchAgents`), plus a `gh` that also answers `repo view`, an `origin` remote, a `launchctl` stub that logs its arguments and exits 1, and `unset ANTHROPIC_MODEL`. HOST_OS Linux keeps launchctl off (hs_os), so setup.sh:610, :619 install no real job.
- A4's fallback, only if a real `claude-openai` run cannot finish: two `--plan` runs, both with the same stubs. `~/.claude/settings.json` is seeded `{}`. Each path the first run lists as "would create" is seeded before the second: `.claude/commandeck.json` with `{"version": <IL_VERSION>}` (install-lib.sh:26, read by the test), so setup.sh:114-116's version check passes; any other .json `{}`; anything else empty. The second run's diff lines are scanned; a "would create … (N lines)" line with N over 30 in it fails the test as an unscanned body.
- No config key is added: `--auto`, `--rules-rewrite` and `--global-rewrite` are not saved, so update.sh (no flags) never rewrites rules again.
- Reference values (the reference setup, read 2026-11-01; its names stay out): routing file `builder-cap` 3 (maxBuilders), `new-test-cap` 3 (a per-unit plan line overrides it there; the plugin's newTestCap, default 40, has no override, so Auto keeps 40: the owner's fourth answer), builder-fix effort medium (fixerEffort), main and Builder opus medium, plan author and both plan judges high, Codex reviewer medium; main settings cache 1h; relay-lane worktree settings cache 1h; Builder worktrees set none (5m); machine settings `defaultMode` auto (`--auto-mode add`); strict on: the reference's project settings register, with no tier gate, all 13 hooks the plugin runs only on the strict tier (plugin hook files calling pp_strict, matched by name to the reference's hook commands, 2026-11-01: 13 of 13), so its working setup is the plugin's `--strict`. trust-all-hooks on and add-ons all: Custom's recommended answers (SKILL.md:150; SKILL.md:224-225), the reference naming neither. Dashboard bind 127.0.0.1: decision 5 and the issue.

## Main answers

- Offload: the Auto report says nothing about a second machine; D11 has no offload line.
- Custom's two Codex seats save `sol`, the newest each launch, not a pinned id (D13).
- Global rules file: Auto merges into `~/.claude/CLAUDE.md` only after a preview that flags each line conflicting with a plugin rule and the owner's answer; nothing is written there without it. Project rule files: rewritten, no preview (D12).
- New-test cap: Auto keeps the plugin default of 40.

## Decisions already made

- D1 Setup's first question is "Setup": Auto Setup (recommended) | Custom. Custom is today's step 1 onward, unchanged. Test: auto-setup.test.sh "the setup skill asks Auto Setup or Custom first and offers Claude + Codex only when the Codex reviewer and model are ready".
- D2 Auto's one question is "Auto profile": Claude + Codex (recommended) | Claude Only when `--questions begin` printed both "Codex reviewer: ready" and "Codex model: found"; else Claude Only (recommended) | Stop (Stop: `--questions end`). Then no question on project files, no preview, Apply or demo build; `--notify-wrapper yes`; a relay behind main is rebased. The one stated exception: D12's global CLAUDE.md question (the owner's third answer). Test: the D1 check; the D12 check.
- D3 `setup.sh --auto <claude-openai|claude>` puts `auto-setup.sh --args <p>` (one per line) in front of the given flags, as `--recommended` does (setup.sh:302-308). The args: `--profile`, `--scope project`, every recommended.json option with the profile's overrides as `--option k=v`, the flags, and the detected values (D4). Claude + Codex overrides: `maxBuilders=3`, `fixerEffort=medium`, `--strict`, relay `Chief of Staff` (a saved name, voice kept), dashboard `--dashboard --bind 127.0.0.1 --hosts ''`, add-ons all as Custom's All: no `--addons` flag, so ADDONS_SET stays empty (setup.sh:514-518, :780), `--trust-all-hooks on`, `--auto-mode add`; recommended caches and review values as they are; no worker cuts or keep words; Codex seats `sol`. Sources: Data design. Test: auto-setup.test.sh "the Claude + Codex args carry every recommended key at the reference values, sol on both Codex seats, --strict and no --addons".
- D4 Detected, not asked: merge check `npm test` (a package.json `test` script other than npm's placeholder) or `make test` (a Makefile `test:` target), else none and `--full-suite off`; typecheck `npm run typecheck` when package.json has a `typecheck` script, else `npx tsc --noEmit` when a root tsconfig.json exists, else none; screen folders `web/src/` when it exists, else none; `--lockfile-deny on` (setup adds rules only for tracked lockfiles); a model setting ending `[1m]` is `--no-standard-context`, else `--standard-context` (none: reported "no model setting found"). Test: auto-setup.test.sh "detected values become the merge check, typecheck, screen folders, lockfile rule and context window"; "odd project files give no merge check and full suite off".
- D5 Claude Only: `codexReviewerAgent=claude`, `codexReviewerModel=opus`, `codexReviewerEffort=medium`, `planJudgeSolAgent=claude`, `planJudgeSolModel=opus`, `planJudgeSolEffort=high`; the rest as D3. Test: auto-setup.test.sh "the Claude Only args run the reviewer and the Sol judge on Claude with opus at the same efforts".
- D6 No pinned version: auto-profile.json, recommended.json, SKILL.md, docs/setup-questions.md, both `--args` outputs, and the body of every file a `setup.sh --auto` run writes match neither `claude-(opus|sonnet|haiku|fable)-[0-9]` nor `gpt-[0-9]`, by Data design's pinned-id scan. Test: auto-setup.test.sh "no Auto profile, recommended set, setup text or Auto run's args names a pinned model version"; "a setup.sh --auto run on a fixture writes no pinned model id into any file it writes".
- D7 Rules: the skill runs `auto-setup.sh --sources` (owner files by key and path, the four templates, the staging folder) and writes each owner file's merged, deduplicated, tightened text (no `<!-- commandeck:` block, front matter kept) and `conflicts.tsv`. Dedupe and conflict-drop run only against the plugin's templates, never across owner files; the plugin's rule wins. A listed file left unstaged, or staged empty, is left as it is and reported, never refused. A linked rule file (Data design, either direction) is listed and left. setup.sh writes in Data design's rewrite sequence. Auto also sends `--rules merge --rules-drop '' --own-startup merge --own-main-session merge` and D12's flags. Its first case runs claim 8. Test: auto-setup.test.sh "a rules rewrite backs up each original, writes the staged text and reports each file, conflict and backup path"; "a listed file left unstaged or staged empty is left as it is and reported"; "a second Auto run the same day after a hand edit keeps the edit byte for byte in an edited copy first"; "a CLAUDE.md that links to AGENTS.md is left as it is and uninstall restores both byte for byte"; "an AGENTS.md linked to CLAUDE.md keeps the Codex block and uninstall restores both byte for byte"; "a same-day Auto rerun with no edit makes no edited copy"; "decline the global file, edit it, uninstall: the edit survives byte for byte"; "an unstaged project file edited after Auto keeps the edit through uninstall".
- D8 il_restore, kind rewrite: the prior blob is written back whatever the file holds, as kind own does (install-lib.sh:1143); when il_rules_same (Data design) with the written blob fails, il_keep_edit copies it first and one line names it: the one reason rewrite is a kind, not own. The kept-backup line becomes "kept setup's copy of <file> as it was on <date>, before setup changed it that day: <path>". Test: auto-setup.test.sh "uninstall after an Auto rewrite puts every original back byte for byte, the global CLAUDE.md included, and removes the backups"; "uninstall after the owner edited a rewritten file puts the original back and keeps the edit beside it"; "Custom on one day and Auto on a later day, then uninstall, puts the original back and the kept backup's line names its day".
- D9 il_rules_check refuses, changing nothing: no folder; a name not in --sources, or listed as linked; a plugin marker; front matter the original opens with and the staged file lacks; a conflicts.tsv line without three fields; a staged `global/CLAUDE.md` with no `--global-rewrite yes|no`. Test: auto-setup.test.sh "a staged rules folder that is absent, names an unlisted or linked file, holds a plugin marker or drops a file's front matter is refused and nothing changes"; "a staged file whose name holds spaces and quotes is written to that one file".
- D10 Rerun, Auto over Custom: each profile answer replaces the saved one, Keep-mine answers are cleared, the first prior stays. Custom over Auto: Custom reads the rewritten files as they are, edits none; uninstall still restores the originals. Test: auto-setup.test.sh "Auto over an earlier Custom setup clears its Keep-mine answers and uninstall still restores the bytes from before Custom"; "Custom after Auto leaves the rewritten text as it is and uninstall still restores the originals".
- D11 Auto's report (`auto-setup.sh --report`): each detected value and where it came from (`merge check: npm test (package.json test script)`, `context window: 200K, no model setting found`), the dashboard's local address, and `bash <plugin>/scripts/setup.sh --dashboard --bind 0.0.0.0 --hosts <name>` to run once `dashboard_serve.py set-password` has stored one. Nothing about a second machine. Test: auto-setup.test.sh "the Auto report prints each detected value with its source, the dashboard's local address and the one command that opens it to the network once a password is set".
- D12 Global CLAUDE.md: the skill stages `global/CLAUDE.md`, runs `auto-setup.sh --global-preview <dir>` (the file now, blocks out, diffed against the staged text; one `CONFLICT:` line per conflicts.tsv row for it, the plugin rule beside it) and asks "Global CLAUDE.md": Optimize it (recommended) | Leave it as it is. Optimize sends `--global-rewrite yes --global-claude merge --global-rules merge` (install when none); Leave sends `--global-rewrite no --global-claude skip --global-rules skip`: no byte written there. The owner sees each dropped line first (P2-6). Test: auto-setup.test.sh "the global CLAUDE.md is previewed with each conflict flagged and written only on a yes".
- D13 recommended.json's two Codex seats become `sol` (:13, :21), so Custom saves the family; the Claude profile still skips them. Test: the D6 recommended-set scan; setup.test.sh:110, :113 kept green.
- D14 `--rules-rewrite` or `--global-rewrite` without `--auto`: refused, nothing changed. Test: auto-setup.test.sh "--rules-rewrite without --auto, or a staged global file with no yes or no answer, is refused and nothing changes".

## Accepted failure modes

- Claude Only reviews on opus, the Builder's family (routing.json:88 says another family): decision 3. Test: the D5 check.
- The global CLAUDE.md rewrite stays until the last project on the machine is uninstalled, as today's global blocks do. Test: the D8 byte-for-byte check, last project.
- A merge that drops an owner's rule is not caught by code; the backup and uninstall bring it back. Test: none, a judgment step; restore is the D8 check.

## Assumptions

- A1 The skill can write the staging folder: [uncertain]. Builder check before C3: add `Write` to SKILL.md allowed-tools and run `claude plugin validate .`; if a path rule (`Write(~/.commandeck/scratch/**)`) validates, keep it, else plain `Write` with the skill text limiting it to the staging folder; log it.
- A2 The new "(recommended)" labels leave plugin.test.sh:52's count of each key's answer at 1: [likely]. Builder check in C3: run plugin.test.sh; on a count of 2, rename the Auto label and log it.
- A3 The readers of an entry's kind: settled (`grep -rn '\.kind' scripts hooks`, 2026-11-01: install-lib.sh:1146, :1148; update.sh:38, :57). update.sh selects `kind != "dir"`, so a rewrite entry is a file to it, as a merge entry is.
- A4 A real `setup.sh --auto` run of each profile finishes on a temp HOME and fixture project with Data design's stubs: [uncertain]; no test in scripts/__tests__ runs setup.sh end to end today (`grep -n setup.sh scripts/__tests__/requirements.test.sh`: its runs stop at the requirements check); scripts/proof-run.sh:101 does, on the stubs the fixture copies. A `--plan` run is no way around the stubs: setup.sh:477 runs the preflight under `--plan` too. Builder check before C1's D6 fixture test: run both profiles with the stubs. If a run stops on another missing tool or file, stub it, log it, run again. If `claude-openai` still cannot finish, use Data design's two-pass fallback (same stubs, `commandeck.json` seeded `{"version": <IL_VERSION>}`) and log it. If that fails too, ask main before C1 closes.

## Steps

- new config/auto-profile.json -- the two Auto profiles as overrides of recommended.json (families only) and flags
- modify config/recommended.json ~13 -- sol on both Codex seats (D13)
- new scripts/auto-setup.sh -- --args, --sources, --global-preview, --report (D3-D5, D7, D11, D12)
- modify scripts/install-lib.sh ~1027 -- il_keep_edit, il_rule_sources (realpath link check), il_rules_check, il_rules_record, il_rules_same, il_rules_rewrite (D7, D9, D12)
- modify scripts/install-lib.sh ~1128 -- il_restore's rewrite branch and the kept-backup line (D8)
- modify scripts/setup.sh ~57 -- --auto, --rules-rewrite, --global-rewrite in TAKES and the parse; D14's refusal (D3)
- modify scripts/setup.sh ~485 -- il_rules_check and il_rules_record before the first change (D7, D9)
- modify scripts/setup.sh ~620 -- il_rules_rewrite before il_global and il_own (D7, D12)
- modify scripts/setup.sh ~790 -- the Auto report lines (D7, D11)
- modify skills/setup/SKILL.md ~5 -- Write in allowed-tools (A1); Auto-scoped words at lines 10-12, 52-58 and 166 (D2)
- modify skills/setup/SKILL.md ~34 -- the first question, Auto's question, the staging, the global question (D1, D2, D7, D12)
- modify docs/setup-questions.md ~1 -- Auto Setup, what it detects, the global question
- modify docs/uninstall.md ~26 -- rewritten rule files come back byte for byte
- modify README.md ~199 -- Auto Setup beside Custom
- new scripts/__tests__/auto-setup.test.sh -- the 25 cases
- modify scripts/__tests__/setup.test.sh ~110 -- expected Codex id sol at :110 and :113 (D13)
- modify CHANGELOG.md ~3 -- the 0.67.0 entry
- modify .claude-plugin/plugin.json ~3 -- version

## Cuts

- C0 Builder starts from main at or after dd9970c. Produces: nothing. Consumes: nothing. Catches: a stale base.
- C1 Profile and args, about 350 lines (auto-profile.json 30, recommended.json 2, auto-setup.sh 120, setup.sh 25, setup.test.sh 2, tests 170). Runs A4 before the D6 fixture test. Produces: the D6 fixture (Data design's stubs, temp HOME, fixture project) and its run helper, the one route every auto-setup.test.sh case runs setup.sh or uninstall.sh by; the fixture is set up at the file's top, so every case, `--args` and `--report` too, runs with no CLAUDE_CONFIG_DIR, CODEX_HOME or ANTHROPIC_MODEL (setup.sh:288, :578; install-lib.sh:28, :719), and the D6 case checks the temp `~/.claude/settings.json` holds `autoMode`; after each run the helper, so the D6 case too, fails on a launchctl log line, a file in the temp `~/Library/LaunchAgents`, or a `launchctl` or `systemctl` that `command -v` finds outside the fixture's bin; `auto-setup.sh --args <p>`, one argument per line; `--report` with each detected value's source; `setup.sh --auto`; D14's refusal; recommended.json's `sol` seats. Consumes: recommended.json options (read only), plugin.json userConfig (opt_check, unchanged), pp_codex_model's family rule (unchanged). Consumers of the changed contracts: setup.test.sh reads TAKES and the parse labels (setup.test.sh:11-24), so the three new value flags go in TAKES; update.sh:68 runs setup with no flags and never meets --auto; recommended.json is read by setup.sh's rec_expand and `--questions begin` lines, setup.test.sh:110 and :113 (edited, D13) and plugin.test.sh:59-71 (both seats default "project", unchanged). Bad input: rows 2 and 4. Catches: a pinned id in a written file, a real launchd or systemd job on the host, a run that reads or writes the owner's Claude or Codex settings, a missing recommended key, a seat left on Codex in Claude Only, a Custom run that rewrites.
- C2 Rules rewrite and restore, about 395 lines (install-lib.sh 120, setup.sh 20, auto-setup.sh 25, tests 230). Produces: il_keep_edit, il_rule_sources (linked files marked by realpath, both directions), il_rules_check, il_rules_record (staged, written-this-run files only, kind merge), il_rules_same (D7 and D8's one comparison), il_rules_rewrite (sole setter of kind rewrite and `written`; the global file's backup in IL_MACHINE), kind rewrite, the reworded kept-backup line. Consumes: il_backup, il_record, il_write, il_block_text, unchanged; C1's fixture and run helper for every setup.sh and uninstall.sh run (the D7, D8, D10 cases). Consumers of il_restore: uninstall.sh:54 and :79, install-lib.test.sh:69 and :142, install-lib-setup.test.sh:76, install-lib-routing.test.sh:43, :132, :146; none records a rewrite, and no test reads the kept-backup line (`grep -rn "kept setup's copy" scripts`, 2026-11-01: install-lib.sh:1131 only). Bad input: rows 1, 3 and 5. Catches: a rewrite with no backup, a same-day edit lost, a spurious edited copy, a linked file overwriting AGENTS.md or its Codex block, uninstall rolling back an edit to a file setup never changed, uninstall leaving a rewritten file "changed since setup", a Custom record hiding the true original.
- C3 Skill and docs, about 106 lines (SKILL.md 60, setup-questions.md 16, README.md 8, uninstall.md 6, test 16). Runs A1 first and A2 after. Consumes: plugin.test.sh's skill checks (:52, :112), kept green; `--global-preview` from C2. Catches: an Ask line outside 2-4 options, Custom text changed beyond the Auto-scoped words.
- C4 CHANGELOG (`## 0.67.0 -- <date>`, a `### Setup` section, user-facing bullets, Custom's Codex seats on the newest model among them) and version, about 9 lines. Catches: version-check's refusal.

## Breaks

Break: scripts/__tests__/auto-setup.test.sh -- a staged rules folder that is absent, names an unlisted or linked file, holds a plugin marker or drops a file's front matter is refused and nothing changes -- install-lib.sh il_rules_check
Break: scripts/__tests__/auto-setup.test.sh -- uninstall after the owner edited a rewritten file puts the original back and keeps the edit beside it -- install-lib.sh il_restore rewrite branch
Break: scripts/__tests__/auto-setup.test.sh -- Auto over an earlier Custom setup clears its Keep-mine answers and uninstall still restores the bytes from before Custom -- install-lib.sh il_rules_rewrite keeping the first prior
Break: scripts/__tests__/auto-setup.test.sh -- a second Auto run the same day after a hand edit keeps the edit byte for byte in an edited copy first -- install-lib.sh il_rules_rewrite edited-copy check
Break: scripts/__tests__/auto-setup.test.sh -- the global CLAUDE.md is previewed with each conflict flagged and written only on a yes -- install-lib.sh il_rules_rewrite global answer
Break: scripts/__tests__/auto-setup.test.sh -- --rules-rewrite without --auto, or a staged global file with no yes or no answer, is refused and nothing changes -- setup.sh parse refusal
Break: scripts/__tests__/auto-setup.test.sh -- decline the global file, edit it, uninstall: the edit survives byte for byte -- install-lib.sh il_rules_record recording only files written this run
Break: scripts/__tests__/auto-setup.test.sh -- an AGENTS.md linked to CLAUDE.md keeps the Codex block and uninstall restores both byte for byte -- install-lib.sh il_rule_sources realpath link check
Break: scripts/__tests__/auto-setup.test.sh -- a same-day Auto rerun with no edit makes no edited copy -- install-lib.sh il_rules_same

## What can go wrong

| case | input or starting state | expected | test |
|---|---|---|---|
| staged rules bad input | staging folder absent or missing; a junk or trailing name --sources did not list; a rule file whose realpath is AGENTS.md's or the global file's, either link direction; a plugin marker; front matter dropped; a conflicts line with two fields (an empty file is no refusal: D7) | refused, exit 1, no file or manifest changed | a staged rules folder that is absent, names an unlisted or linked file, holds a plugin marker or drops a file's front matter is refused and nothing changes |
| flag bad input | `--rules-rewrite` without `--auto`; with a staged global file, `--global-rewrite` absent, empty, junk (`maybe`) or quoted (`'yes '`) | refused, exit 1, nothing changed | --rules-rewrite without --auto, or a staged global file with no yes or no answer, is refused and nothing changes |
| quoted file name | `.claude/rules/my "team" rules.md` | that one file written, its backup beside it | a staged file whose name holds spaces and quotes is written to that one file |
| odd project files | no package.json; junk JSON; an empty test script; npm's placeholder test; a test script with quotes; no model setting | no merge check and full suite off; the quoted script is sent as `npm test`; window 200K, reported "no model setting found" | odd project files give no merge check and full suite off |
| same-day rewrite after an edit | Auto, a hand edit, Auto again the same day; or Custom, an edit, Auto the same day | the edit kept byte for byte at `<file>.commandeck-edited-<date>`, named, before the rewrite | a second Auto run the same day after a hand edit keeps the edit byte for byte in an edited copy first |

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- 4 reference routing keys have no plugin key and are left out (classStop, typecheckSeconds, backgroundMaxMinutes, effort stages; read 2026-11-01).
- Downgrade: an older plugin's uninstall leaves a rewritten file as it is ("changed since setup") and keeps its backups; 1 schema version, no migration (`grep -n IL_VERSION= scripts/install-lib.sh`, 2026-11-01: :26).

## Not in this unit

- Anything about a second machine: Auto names none (the owner's first answer).
- Out of scope, for main: scripts/proof-run.sh:101 likely fails at main: its `gh` stub answers only `auth token` (:44) and the sample has no origin remote (:60), so review_gh_check (paths.sh:1296-1297) refuses every profile; main files it.

## Acceptance test

- test file path: scripts/__tests__/auto-setup.test.sh (the setup skill asks Auto Setup or Custom first and offers Claude + Codex only when the Codex reviewer and model are ready; the Claude + Codex args carry every recommended key at the reference values, sol on both Codex seats, --strict and no --addons; the Claude Only args run the reviewer and the Sol judge on Claude with opus at the same efforts; no Auto profile, recommended set, setup text or Auto run's args names a pinned model version; a setup.sh --auto run on a fixture writes no pinned model id into any file it writes; detected values become the merge check, typecheck, screen folders, lockfile rule and context window; odd project files give no merge check and full suite off; the Auto report prints each detected value with its source, the dashboard's local address and the one command that opens it to the network once a password is set; a rules rewrite backs up each original, writes the staged text and reports each file, conflict and backup path; a listed file left unstaged or staged empty is left as it is and reported; a staged rules folder that is absent, names an unlisted or linked file, holds a plugin marker or drops a file's front matter is refused and nothing changes; a staged file whose name holds spaces and quotes is written to that one file; --rules-rewrite without --auto, or a staged global file with no yes or no answer, is refused and nothing changes; the global CLAUDE.md is previewed with each conflict flagged and written only on a yes; a second Auto run the same day after a hand edit keeps the edit byte for byte in an edited copy first; a CLAUDE.md that links to AGENTS.md is left as it is and uninstall restores both byte for byte; an AGENTS.md linked to CLAUDE.md keeps the Codex block and uninstall restores both byte for byte; a same-day Auto rerun with no edit makes no edited copy; decline the global file, edit it, uninstall: the edit survives byte for byte; an unstaged project file edited after Auto keeps the edit through uninstall; uninstall after an Auto rewrite puts every original back byte for byte, the global CLAUDE.md included, and removes the backups; uninstall after the owner edited a rewritten file puts the original back and keeps the edit beside it; Custom on one day and Auto on a later day, then uninstall, puts the original back and the kept backup's line names its day; Auto over an earlier Custom setup clears its Keep-mine answers and uninstall still restores the bytes from before Custom; Custom after Auto leaves the rewritten text as it is and uninstall still restores the originals)
- Existing, kept green: setup.test.sh, plugin.test.sh, merge-rules.test.sh, install-lib.test.sh, install-lib-setup.test.sh, install-lib-routing.test.sh, update.test.sh, requirements.test.sh.

## Claims to falsify

- `auto-setup.sh --args claude-openai` lists each config/recommended.json key once.
- `auto-setup.sh --args claude` leaves no seat on agent codex.
- No pinned id is in auto-profile.json, recommended.json, SKILL.md, docs/setup-questions.md, either --args output, or any file a fixture Auto run writes but unchanged view copies.
- A refused --rules-rewrite leaves every rule file and both manifests as they were.
- After Auto, uninstall: every owner rule file, linked ones and AGENTS.md too, has its pre-setup sha256.
- With AGENTS.md linked to CLAUDE.md, CLAUDE.md holds the plugin's Codex block after Auto.
- A file Auto declined or left unstaged, then edited, has its edited sha256 after uninstall.
- After the global-yes case, `jq -e '[.entries[] | select(.kind=="rewrite")] | length > 0 and all(has("written"))'` passes on both manifests.
- A same-day Auto rerun with no edit creates no `.commandeck-edited-` file.
- After Custom, Auto, uninstall: AGENT_STARTUP.md has its sha256 from before Custom.
- A hand edit between two same-day Auto runs survives byte for byte beside the file.
- With `--global-rewrite no`, ~/.claude/CLAUDE.md keeps each byte.
- A Custom run after Auto writes no byte of the owner's text outside a marked block.
- update.sh after Auto edits no rule file.
- SKILL.md's Custom part changes only the first question's lead-in and lines 10-12, 52-58, 166.
- No fixture run logs a launchctl call or leaves a file in the temp LaunchAgents.
- Run with CLAUDE_CONFIG_DIR, CODEX_HOME and ANTHROPIC_MODEL set, auto-setup.test.sh passes, both folders empty.

## Verification

- `bash scripts/run-shell-tests.sh --changed main` during the build (on the PC through the hand-off).
- `CLAUDE_CONFIG_DIR=$(mktemp -d) CODEX_HOME=$(mktemp -d) ANTHROPIC_MODEL='x[1m]' bash scripts/__tests__/auto-setup.test.sh` passes and both folders stay empty.
- `git diff main -- skills/setup/SKILL.md` shows the Custom steps unchanged but the Auto-scoped words.
- `claude plugin validate .`, `claude plugin test .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh` pass; the full shell suite green on the PC before any push.
- Review passes until a closing pass says `VERDICT: GO` naming no finding.

## Issue cases

- #536 Body 1 -- skills/setup/SKILL.md -- the setup skill asks Auto Setup or Custom first and offers Claude + Codex only when the Codex reviewer and model are ready
- #536 Body 2 -- skills/setup/SKILL.md -- Custom after Auto leaves the rewritten text as it is and uninstall still restores the originals
- #536 Body 3 -- config/auto-profile.json -- the Claude + Codex args carry every recommended key at the reference values, sol on both Codex seats, --strict and no --addons
- #536 Body 4 -- config/auto-profile.json -- the Claude Only args run the reviewer and the Sol judge on Claude with opus at the same efforts
- #536 Body 5 -- skills/setup/SKILL.md -- the setup skill asks Auto Setup or Custom first and offers Claude + Codex only when the Codex reviewer and model are ready
- #536 Body 6 -- scripts/auto-setup.sh -- detected values become the merge check, typecheck, screen folders, lockfile rule and context window
- #536 Body 7 -- scripts/install-lib.sh -- the global CLAUDE.md is previewed with each conflict flagged and written only on a yes
- #536 Body 8 -- scripts/install-lib.sh -- uninstall after an Auto rewrite puts every original back byte for byte, the global CLAUDE.md included, and removes the backups
- #536 Body 9 -- scripts/install-lib.sh -- a rules rewrite backs up each original, writes the staged text and reports each file, conflict and backup path
- #536 Body 10 -- scripts/setup.sh -- a rules rewrite backs up each original, writes the staged text and reports each file, conflict and backup path
- #536 Body 11 -- scripts/auto-setup.sh -- the Auto report prints each detected value with its source, the dashboard's local address and the one command that opens it to the network once a password is set
- #536 Body 12 -- scripts/install-lib.sh -- Auto over an earlier Custom setup clears its Keep-mine answers and uninstall still restores the bytes from before Custom
- #536 Body 13 -- scripts/__tests__/auto-setup.test.sh -- uninstall after the owner edited a rewritten file puts the original back and keeps the edit beside it

## Done

- #536 Done: an owner runs /commandeck:setup, picks Auto Setup, then Claude + Codex -- setup applies the full profile with no question on project files and lists each rewritten rule file, each settled conflict and its backup path
- #536 Done: an owner whose Codex is not ready picks Auto Setup -- only Claude Only is offered, and reviews and the second plan judge run on Opus
- #536 Done: an owner with a global CLAUDE.md picks Auto Setup -- they see its planned change with each conflicting line flagged, and it changes only if they pick Optimize it
- #536 Done: an owner uninstalls after Auto Setup -- every rule file they had holds its exact bytes from before setup again, an edit they made in between sits in a file beside it, and a file setup never changed keeps their edits
- #536 Done: an owner picks Custom -- the same questions as before, and setup never edits their rule text
- #536 Done: an owner reads the Auto report -- each detected value with where it came from, and the dashboard on for this machine with the one command that opens it to the network once a password is set

## Routing

- Builder: one, Opus; helpers Sonnet `general-purpose` for the test file and the docs, Haiku `Explore` for search.
- Reviews: the default workflow; closing pass last.

## Plan change log

- 2026-11-01 plan written from the issue, the spec and the reference setup's values.
- 2026-11-01 owner's addition (no pinned versions) folded into D3, D5, D6.
- 2026-11-01 r2 owner answer 1 (P2-8): D11's offload line and all tied to it (test, Done line, stated limit, Not-in-unit item) removed.
- 2026-11-01 r2 owner answer 2: D13 (recommended.json `sol`), the Test edits line, two Steps, C1's consumers.
- 2026-11-01 r2 owner answer 3: D12 (global preview, conflicts flagged, written only on yes), D2's one exception, D9 and D14 refusals, Issue case Body 7, a Done line.
- 2026-11-01 r2 P1-1: D7's same-day edited copy (il_keep_edit, shared with D8), WCGW row 5, a Break, a test.
- 2026-11-01 r2 P1-2: priors recorded at the manifest step; linked rule files left as they are and refused if staged (D7, D9); a test; claim 5 now names the link.
- 2026-11-01 r2 P2-3: D4's typecheck condition and no-model-setting line; D11 reports each detected value's source.
- 2026-11-01 r2 P2-4: D6 scans every file a fixture `setup.sh --auto` run writes; A4; a test.
- 2026-11-01 r2 P2-5: an unstaged or empty staged file is left and reported (D7, D9); a test.
- 2026-11-01 r2 P2-6: dedupe and conflict-drop only against the plugin's templates (D7); the global file per D12.
- 2026-11-01 r2 P2-7: SKILL.md lines 10-12, 52-58 and 166 named as Auto-scoped edits (Steps); the last claim updated.
- 2026-11-01 r2 P3-9: the downgrade stated limit.
- 2026-11-01 r2 P3-10: D8 says why rewrite is a kind; auto-profile.json holds overrides (Data design, C1).
- 2026-11-01 r2 P3-11: D14, WCGW row 2, a Break, a test.
- 2026-11-01 r2 P3-12: D8's kept-backup line reworded; a later-day test.
- 2026-11-01 r2 D3 spot-check: Reference values in Data design; new-test cap asked as Q1; strict, trust-all-hooks, add-ons, bind in no reference file read.
- 2026-11-01 r2 A3: update.sh:38, :57 also read kind; New tests 15 to 21; 615 to 770 lines, 13 files.
- 2026-11-01 r3 owner answer (Q1): new-test cap 40 in Main answers; the owner question removed.
- 2026-11-01 r3 P1-1: il_rules_record: staged, non-empty, written-this-run files only (global only on yes), kind merge; il_rules_rewrite alone sets rewrite and `written` (Data design, D7, C2); two tests, a Break, two claims, a Done clause.
- 2026-11-01 r3 P2-2: `--strict` kept, sourced: the reference registers all 13 plugin strict-tier hooks ungated (Data design, D3, Facts); D3's test name adds --strict.
- 2026-11-01 r3 P2-3: D6's plan scan seeds each would-create path so every body prints, else fails; now A4's fallback.
- 2026-11-01 r3 P2-4: linked = realpath equal to AGENTS.md's or IL_GLOBAL's, both directions (D7, C2, WCGW row 1); a reverse-link test, a Break, a claim.
- 2026-11-01 r3 P3-5: SKILL.md:150 and :224-225 cited; add-ons all sends no `--addons` (D3, Data design, Facts); D3's test name adds no --addons.
- 2026-11-01 r3 P3-6: one comparison, il_rules_same, for D7 and D8 (Steps, C2); a no-edit same-day rerun test, a Break, a claim.
- 2026-11-01 r3 P3-7: the global file's backup recorded in IL_MACHINE (Data design, D7, C2).
- 2026-11-01 r3 size: New tests 21 to 25; 770 to 850 lines; C1 340, C2 395.
- 2026-11-01 r4 P2-B: both profiles run for real on the preflight's stubs, every file under temp HOME and project scanned; two-pass `--plan` only as A4's fallback, same stubs; A4's reason corrected (setup.sh:477) (Data design, D6, A4, Facts).
- 2026-11-01 r4 P2-A: the fallback seeds `.claude/commandeck.json` with `{"version": <IL_VERSION>}` (install-lib.sh:26), never `{}` (Data design, A4, Facts).
- 2026-11-01 r4 P3-C: the rewrite-backup case also runs claim 8's `has("written")` jq on both manifests; no new case.
- 2026-11-01 r5 P2-D: the fixture copies proof-run.sh:31-52's stubs plus a `gh` answering `repo view` and an origin remote; no real launchd or systemd job (Data design, A4, Prior art, Facts).
- 2026-11-01 r5 P3-E: claim 8's jq also needs at least one rewrite entry (`length > 0 and all(has("written"))`).
- 2026-11-01 r5 size: Facts bullets merged, adjacent cites joined to fit the cap; no fact dropped.
- 2026-11-01 r5 judge note: proof-run.sh:101's likely failure at main listed as "Out of scope, for main", with its Facts.
- 2026-11-01 r6 P2-F: the pinned-id scan skips the 3 dashboard view files only while `cmp` equals the plugin's copy (app.js:334 names an id in a comment) (Data design, Facts).
- 2026-11-01 r6 P2-G: every case that runs setup.sh or uninstall.sh uses the D6 fixture through C1's run helper (C1 Produces, C2 Consumes).
- 2026-11-01 r6 P3-H: a logging `launchctl` stub that exits 1; the helper, so the D6 case, fails on a launchctl log line, a file in the temp LaunchAgents, or launchctl/systemctl outside the fixture bin (Data design, C1, a claim). Claim 3 names the view-file skip. Nits fixed. Size 860.
- 2026-11-01 r7 P2-I: the fixture, at the test file's top, copies proof-run.sh:29-52 (its config-path `unset`) and unsets ANTHROPIC_MODEL; the D6 case checks `autoMode` in the temp settings; a claim, a Verification run with the three set (Data design, Prior art, C1, Facts).
- 2026-11-01 r7 nit: C1's Catches names a host job and the owner's settings. Data design, Claims, Facts (cites joined) and this log reworded to fit caps; nothing dropped.

## Facts

- Requirements first; Codex offered only on "Codex reviewer: ready"; Custom detects merge check, typecheck (npm's only with that script), screen folders, previews, asks Apply; README says so -- skills/setup/SKILL.md:34-38, skills/setup/SKILL.md:65-69, skills/setup/SKILL.md:173-191, skills/setup/SKILL.md:261-277, README.md:199-245 (observed: 2026-11-01)
- Skill: preview, no rules edit, Apply first, no unasked rebase; tools bash, python3, picker; recommends trust-all Yes, strict Off, add-ons All with no --addons -- skills/setup/SKILL.md:5, skills/setup/SKILL.md:10-12, skills/setup/SKILL.md:52-58, skills/setup/SKILL.md:150, skills/setup/SKILL.md:166, skills/setup/SKILL.md:192-195, skills/setup/SKILL.md:223-225 (observed: 2026-11-01)
- Value flags in TAKES; Codex lines and an unknown model setting printed; --recommended's options first; --global-claude values; the model setting from ANTHROPIC_MODEL first -- scripts/setup.sh:57, scripts/setup.sh:278-293, scripts/setup.sh:302-308, scripts/setup.sh:339-340 (observed: 2026-11-01)
- Manifest step before any change; global file recorded only on install, block or merge; no --addons: every add-on, serena hooks on, a Needs-you line; IL_WROTE shadows deleted at exit; AGENTS.md block, global blocks, own merges later; autoMode into CLAUDE_CONFIG_DIR's settings -- scripts/setup.sh:485, scripts/setup.sh:512-530, scripts/setup.sh:578-583, scripts/setup.sh:620-627, scripts/setup.sh:780 (observed: 2026-11-01)
- recommended.json pins gpt-6.1-sol on two seats; fixer high; review and cache values -- config/recommended.json:12-40 (observed: 2026-11-01)
- A model is a family, a Codex family the newest; reviewer on another family; new-test cap 40; maxBuilders a key -- config/routing.json:9, config/routing.json:88, scripts/paths.sh:926-945, scripts/builder-codex-pass.sh:501, .claude-plugin/plugin.json:202 (observed: 2026-11-01)
- No migration; AGENTS.md, global paths; write through a link; a plan shows a big created file by length, shadows keep bodies; Codex files under CODEX_HOME -- scripts/install-lib.sh:26-100 (observed: 2026-11-01)
- First record kept; il_backup skips a same-day copy; blank line before a block; skip leaves the global file; il_global uses IL_MACHINE; own merge keeps owner text; il_same ignores trailing blanks; an equal backup goes, else the kept line; own restores regardless, an edited merge is left -- scripts/install-lib.sh:113-135, scripts/install-lib.sh:992-1083, scripts/install-lib.sh:1109-1145 (observed: 2026-11-01)
- Strict-tier hooks exit unless strictHooks is set -- hooks/lib/project.sh:54-59, hooks/read-tracker.sh:6-7, hooks/suite-rerun-guard.sh:35-36 (observed: 2026-11-01)
- Uninstall: AGENTS.md block out, restore, global last, autoMode removed; update: no flags, every non-dir entry -- scripts/uninstall.sh:39-79, scripts/install-lib.sh:719, scripts/update.sh:38-68 (observed: 2026-11-01)
- Version check; --plan still preflights: companion, prompt template, codex login, gh with an origin; sol from models_cache -- scripts/setup.sh:84-116, scripts/setup.sh:477, scripts/builder-codex-pass.sh:105-110, scripts/builder-codex-pass.sh:1067-1094, scripts/builder-codex-pass.sh:1155-1162, scripts/paths.sh:926-937, scripts/paths.sh:1296-1297 (observed: 2026-11-01)
- launchctl only if hs_os is Darwin, else systemctl; 3 view files copied whole, app.js names an id; proof-run.sh: config overrides unset, HOST_OS Linux, stubs, gh only auth token, no origin -- scripts/setup.sh:610-619, scripts/main-watch.sh:104, scripts/host-services.sh:18, scripts/dashboard.sh:43-60, scripts/dashboard.sh:1400-1450, scripts/dashboard.sh:1605-1612, dashboard/app.js:334, scripts/proof-run.sh:29-101 (observed: 2026-11-01)
- setup.test.sh reads TAKES, expects gpt-6.1-sol twice; plugin.test.sh counts labels, options -- scripts/__tests__/setup.test.sh:11-24, scripts/__tests__/setup.test.sh:110-113, scripts/__tests__/plugin.test.sh:52, scripts/__tests__/plugin.test.sh:112 (observed: 2026-11-01)

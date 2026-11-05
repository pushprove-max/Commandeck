# rules-port-2026-11-04 -- port the host project's 2026-11-04 rules cleanup into the plugin

Owner's words: the owner, 2026-11-04: build one plugin unit that ports all of the host project's 2026-11-04 rules cleanup.
Owner addition: change opus fixer from high to medium going forward (the owner, 2026-11-04, relayed by main into this revision)
Goal: Port every applicable W item of the host's 2026-11-04 rules cleanup into the plugin's scripts, templates and docs; record each host-only item with its reason.
Tier: Standard; LOCAL merge; changed-file tests on the PC; full shell suite on the PC before the merge; no timeout raises.
Closes: #661
Base: local main 5cc7eb8
Build order: C1, C2, C3, C4, C5, Release (one after another, one build slot)
New tests: rules-port-2026-11-04 12
Timed checks: none; no heavy fixture is added to a file with time-bound checks
Merge message: `Closes #661` when every row of the W table is built; `Refs #661` if any is left partial
- Planned size: 33 files, 490 changed lines

## Why

The host project removed its review pass cap, moved a few rules to one home and tidied main's card. The plugin carries the same rules in its templates and the same cap-stop code in its pass script. Each W item below is matched to its plugin file by rg; where the plugin has the rule already in one place, or never had it, the item is host-only and is recorded here. The plugin's pass cap is an owner setting (`reviewPassCap`), so the setting stays and only the stop goes: from that pass every pass is a closing pass, and a P0 or P1 still open two passes later is the REVIEW STOP (pass 7 by default). This is the smallest full port: no key rename, no config change, no new file.

## Prior art

- Standard: the host's own cleanup diff (read for what changed; nothing quoted from it) and the plugin's templates and scripts.
- Library or service: none new. Bash, awk and python3 as the scripts already use them.
- Why build: the rules are the plugin's own text; no tool ports them.

## Data design

none: no state is added or changed. `reviewLoop.passCap` / `reviewPassCap` keeps its key, type and saved values (D2); the relay's saved state file is read, never written (D7).

## W table

| W | Plugin file(s) | Port? | Reason | Test |
|---|---|---|---|---|
| W3 no pass cap | builder-codex-pass.sh, main-watch.sh, merge-unit-local.sh, builder-launch.sh, setup.sh, brief template, main-rulings, global-rules, README, docs, setup skill, plugin.json | port | same cap stop, gate, texts; review-cap.sh's owner-set round limit kept (D12) | P2-only pass 6 launches; rule text carries no pass cap; watcher REVIEW STOP names no pass number |
| W8 handoff first | hooks/agent-startup-context.sh | port | state printed unordered, no warning | newest handoff first, one over-cap warning |
| W13 serena for Builders | main-session.md, global-rules.md | port | card says "serena for symbols" | removed rules gone from templates |
| W17 no old-data support | global-rules.md | port | "ask before building backward compatibility"; rollout rule unchanged | removed rules gone from templates |
| W26 restart reports | main-session.md | port | bans reporting restarts | removed rules gone from templates |
| W27 keep-list, CLI text | none | host-only | Codex file has no keep-list, no generator copies one; Codex reads the startup file's one keep-list; no CLI-binaries text | host-only items stay single |
| W29 fallbacks | none | host-only | product rules; no app code, no such section | host-only items stay single |
| W35 over-engineering | global-rules.md | port (part) | the alternatives rule names "a file", which the host dropped; one home already; the 200-line check was never a plugin rule | removed rules gone from templates; host-only items stay single |
| W36 tag unverified | global-rules.md | port | tags every claim | removed rules gone from templates |
| W37 wake detail | none | host-only | card holds one wake bullet; detail is in Details | host-only items stay single |
| W44 announce once | main-session.md | port | one-status-line rule; announce every worker | announce worker once, no status-line rule |

## Cuts

### C1 (#661 W3) the cap stop goes from the scripts -- est. 230 lines
- Produces: `--verify` never merges a NO-GO; the proof rule is `closing GO`, `threshold stop`, `first-pass GO` or `no closing pass`, never `cap stop`; no `STOP (cap)` line; no cap gate refusal; the pass script's REVIEW STOP texts (:945, :1332, :1335, :2444; comments :941, :1323) say "at pass $((REVIEW_CAP + 2)) or later", REVIEW_CAP being the pass script's own variable (:439).
- Removes in scripts/builder-codex-pass.sh: the cap clauses of the header (:26-36) and the REVIEW_CAP comment (:436-438); `cappable_count` (:445-447); `CAP_LEVELS` (:126-128, used only by cap texts); `CAPPED` and the at-cap NO-GO branch (:944, :955-964), so every NO-GO dies; `cap stop` in the rule (:1042) and in `ENDED_AS` (:1088); `cap_gate_reason`, its plan-only check and refusals (:1337-1375); the `STOP (cap)` branch (:2454-2457).
- Keeps: `REVIEW_CAP` (:439) as the point from which `review` runs as `final` (:1404-1406, text "final in place of review: this is pass <n> on record, pass <REVIEW_CAP> or later, where every pass is a closing pass"; the pinned prefix is unchanged) and `review_stop_id` at REVIEW_CAP + 2; the P0/P1 die text "a P0 or P1 is never capped" (:957) and the below-anchor die text "holds the merge below the cap" (:960) for a count under REVIEW_CAP; at or past it the die says "holds the merge (pass <n> on record): passes run until clean". `STOP (threshold)` unchanged.
- Keeps (D12): the owner-set round limit (:1217-1226, `<unit>-review-cap.md`, written only by main's scripts/review-cap.sh:18); its comment :1218-1219 says "the Closing pass from setting (reviewPassCap) never refuses a pass".
- scripts/main-watch.sh: stop_next (:962-980) drops the cap-stop branch and its comment; main-watch has no REVIEW_CAP and reads no passCap, so its REVIEW STOP text names no pass number: "a P0 or P1 is still open two passes after the Closing pass from setting (reviewPassCap)". Right for any saved value (99 too).
- scripts/builder-launch.sh:348: the passCap brief line says "from the <n>th pass on the reviewer's record every pass is a closing pass, and a P0 or P1 still open two passes later stops for the owner".
- Consumes: pp_review_loop passCap (scripts/paths.sh:1142, :1255), unchanged.
- Existing consumers: main-watch.sh stop_next parses `REVIEW STOP:`, `decision <id>;` and `ended NO-GO` (:974-975): every new text keeps those tokens; merge-unit-local.sh takes any Builder proof and its code names no cap stop (its comments do: C2); unit-ledger.sh records the proof rule (unchanged).
- Tests (D9): delete scripts/__tests__/builder-codex-pass-cap-gate.test.sh (9 checks on the removed gate); in builder-codex-pass-threshold-cap.test.sh replace :48 with "P2-only pass 6 launches", delete :94 (a cap of 3 is a cap stop), keep :99, and move the cp fixture (:44-47) from a cap stop to a threshold stop (pass 5 a closing GO with two P3s on cp.txt and one with no place), so :50-62's filing claims and texts hold unchanged; builder-codex-pass-threshold.test.sh:138 expects the verify refusal without 'names no open P2'; comment-only rewording in that file (:2-4, :134-135), threshold-cap (:3-9), merge-unit-local.test.sh:45-46, builder-codex-pass-closing.test.sh:14, -decisions.test.sh:75, -rebase.test.sh:59, -class-return.test.sh:19; main-watch-report-wake.test.sh gains "watcher REVIEW STOP names no pass number" after :103 (D11: :101's fixture is not edited).

### C2 (#661 W3) the cap leaves the rule text and docs -- est. 70 lines
- Produces: templates/_builder-brief-template.md (:278-286, :359-360) says passes run until clean, two lines end the loop (`STOP (threshold)`, `REVIEW STOP` at pass 7 by default), no later-pass refusal; templates/main-rulings.md:15 drops "or a cap stop"; templates/global-rules.md:40-43 "Done is one of the pass's stop lines: a closing pass that ends GO (P3 findings alone are GO); passes run until clean" (no closing NO-GO at the review cap); scripts/merge-unit-local.sh comments :373-377, :408-409, :544 name no cap; scripts/setup.sh:158, :307, :381 "pass cap" -> "closing pass from" (D8 title); README.md diagram (:112, :116, :128-133) and :246, :316-319, :348, :386, :474; docs/review-loop.md:126-152; docs/configuration.md:101-107; docs/setup-questions.md:58; skills/setup/SKILL.md:272-279; .claude-plugin/plugin.json:191-192 per D8.
- Tests (D9): brief-template.test.sh:101 and :103 expect the new template sentences; new check "rule text carries no pass cap": the Claims to falsify review-loop rg over its 14 files counts 0.
- Consumes: C1's behaviour. Existing consumers: plugin.test.sh:86-88 refuses 'No cap|--max-rounds|maxReviewRounds' in SKILL, setup and the manifest: no new text uses those strings.

### C3 (#661 W13 W17 W26 W36 W44) main's card and the global rules -- est. 45 lines
- templates/main-session.md:15 "(serena for symbols)" -> "(`rg` for symbols; serena is for Builder seats only)"; :154 "A lookup serena or one `rg` answers" -> "A lookup one `rg` answers"; :30-31 the one-status-line bullet goes; :131 -> "Announce a worker once, at dispatch (agent, model, worktree, task)"; :38 drops "do not report how often main restarts and", keeps "do not propose moving the line".
- templates/global-rules.md:5-6 -> "No old-data support by default: write no migration, compatibility branch, legacy fallback, dual read or write, or old-shape case. Ask the owner only when a live old-shape row, token or record is known to exist, and give the count."; :67-68 -> "Tag only a claim you did not verify: [likely] (inferred, not run) or [uncertain]; a claim you ran or read needs no tag. \"I did not check X\" is useful."; :164-166 adds "main finds them with rg; a symbol tool is for Builder seats only"; :173-174 (W35) -> "A plan step that adds an abstraction, a config surface or a dependency names the simplest alternative it considered and why that loses." (the host dropped "new file").
- Tests (D9): template-sections.test.sh:24's row takes the new clear-line sentence, and PORTED gains a row per new sentence; new checks "removed rules gone from templates" (W35's "a dependency or a file" among them) and "host-only items stay single"; agent-startup-context.test.sh:120 becomes "announce worker once, no status-line rule".
- Lineage (D13): scripts/merge-rules.py MADE_FROM (:114-178) gains a `# 0.72.0` line pairing each rule C2 and C3 reword with its old id, as every rewording release does: main-session 401e8893, 5ea4eaeb, 4f772079, 80518d00; global-rules 419f6ca9, 26b6b2b9, 671886ae, 6ba05b23, a935667e. The new ids come from `python3 scripts/merge-rules.py templates/<file>.md --units` on the built text (for the plan's exact wording: bce76243, 7438dcb8, 48bcb4c0, b3b54a7c, d501f34e, a565c8bd, 49596746, 88d5a452, b116e4dc). The status-line rule (432067c4) is removed, not reworded: no line.
- Tests (D13): merge-rules.test.sh keeps every check, re-pointed at the new ids: :28 "19 plugin rules kept" -> 18 (the removed status-line rule) and its comment :21; :46 "1:42" -> "1:41"; :58 pairs 401e8893:71c7e94b and 80518d00:b2577b20 take the new id, old anchor kept; :66-67 and :71's 26b6b2b9 and a935667e likewise.
- Existing consumers: hooks/agent-startup-context.sh injects main's Working rules and the startup file (unchanged); brief-template.test.sh:148-160 rule-drift checks read other sentences (unchanged); setup's rule merge (merge-rules.py) leaves out a rule by saved id, kept by the lineage above.

### C4 (#661 W8) the relay's state, newest handoff first -- est. 60 lines
- hooks/agent-startup-context.sh:153-157: `-s` in place of `-f`; split the state at `## ` headings; the first section printed is the first heading holding "handoff" and "newest" (case-insensitive), else the last heading holding "handoff", else none moves; the rest keep file order; the 5000-byte whole-line cut and its pointer line apply to the reordered text; over 5000 bytes one line `# WARNING: <file> is <n> bytes, over its 5000-byte cap: trim it.` prints after the state header line.
- Tests: five new checks in hooks/__tests__/agent-startup-context.test.sh (Acceptance test).
- Existing consumers: none read this output but the relay pane; the cos watchers read other state files (cos-lib.sh:4).

### C5 (owner addition) the recommended fixer effort is medium -- est. 6 lines
- Produces: config/recommended.json:12 `"fixerEffort": "medium"`; setup's Recommended set and Auto Setup send medium for later fix rounds.
- Owner's saved value: setup saves options in settings.json pluginConfigs (paths.sh:1191-1196); no settings.json of the owner's holds a fixerEffort (Assumptions), so the value in force is routing's medium (routing.json:65-68): nothing to write.
- Keeps: config/auto-profile.json:7's medium pin, now equal to the base; auto-setup.test.sh:111 passes unchanged.
- Tests: plugin.test.sh gains "recommended fixer at medium" after :66, as :65-66 pins the Builder's.
- Consumes: none. Existing consumers: setup.sh's Recommended set and setup.test.sh:98-110 read values from the file; auto-setup.sh:61-62 and auto-setup.test.sh:109-111; plugin.test.sh:63-64 skips a "project" default. No doc names the recommended fixer effort (rg, 2026-11-04).

### Release -- est. 17 lines
- CHANGELOG.md 0.72.0 in the newest entries' plain style (### Scripts, ### Templates, ### Hooks, ### Config); .claude-plugin/plugin.json version 0.72.0; README.md:4 badge 0.71.0 -> 0.72.0 in both the image URL (`badge/version-0.72.0-`) and the alt text (`Version 0.72.0`).
- Existing consumers: plugin.test.sh:33-35 require the README badge and the CHANGELOG's newest entry to match the manifest version (unchanged).

## Routing

- Builder helpers name the model on every call: Sonnet general-purpose for test edits and mechanical text edits per cut; Haiku Explore for searches.
- Codex passes run until clean.

## Steps

- modify scripts/builder-codex-pass.sh ~944 -- no cap stop or gate; REVIEW STOP at REVIEW_CAP + 2
- modify scripts/main-watch.sh ~962 -- no cap stop; REVIEW STOP names no pass number
- modify scripts/merge-unit-local.sh ~373 -- comments name no cap
- modify scripts/setup.sh ~158 -- "closing pass from" for "pass cap"
- modify scripts/__tests__/main-watch-report-wake.test.sh ~103 -- the watcher check
- modify scripts/builder-launch.sh ~348 -- passCap brief line: closing pass from n
- delete scripts/__tests__/builder-codex-pass-cap-gate.test.sh -- the removed gate's checks
- modify scripts/__tests__/{builder-codex-pass-threshold-cap,builder-codex-pass-threshold}.test.sh -- P2-only pass 6; cp fixture; :138
- modify scripts/__tests__/{merge-unit-local,builder-codex-pass-closing,builder-codex-pass-decisions,builder-codex-pass-rebase,builder-codex-pass-class-return}.test.sh -- comments only
- modify templates/{_builder-brief-template,main-rulings}.md -- passes run until clean
- modify {README.md,docs/review-loop.md,docs/configuration.md,docs/setup-questions.md,skills/setup/SKILL.md} -- closing-pass point
- modify scripts/__tests__/brief-template.test.sh ~101 -- new sentences; no pass cap
- modify templates/main-session.md ~15 -- C3 card rules
- modify templates/global-rules.md ~5 -- C2 Done text; C3 rules (old data, tags, rg, W35)
- modify scripts/__tests__/template-sections.test.sh ~24 -- ported rows; C3 checks
- modify scripts/{merge-rules.py,__tests__/merge-rules.test.sh} ~178 -- 0.72.0 lineage; new ids, every check kept (D13)
- modify hooks/agent-startup-context.sh ~153 -- newest handoff first; warning; empty silent
- modify hooks/__tests__/agent-startup-context.test.sh ~120 -- relay state cases; announce once
- modify config/recommended.json ~12 -- fixerEffort high -> medium (owner addition)
- modify scripts/__tests__/plugin.test.sh ~66 -- fixer recommended at medium
- modify {CHANGELOG.md,.claude-plugin/plugin.json,README.md} -- 0.72.0, badge; D8

## Decisions already made

1. D1 The rule-drift map is the host's file, read by the host's drift tool; this plugin unit cannot write it (LOCAL merge in the plugin repo). The W table is the record; main marks the host-only rows and re-syncs the ported ones in the host after the merge (Follow-ups).
   Test: none, the map is outside this repo
2. D2 `reviewPassCap` / `passCap` keeps its key and saved values (D8): it sets where every pass becomes a closing pass and where a P0/P1 stops (n + 2); it never ends the loop. A rename would need old-config handling, and a saved value is known to exist (this checkout's 99).
   Test: P2-only pass 6 launches
3. D3 A NO-GO never merges, at any pass count; the at-cap merge branch and `cap stop` rule go, and so does the gate that refused passes after it (nothing stops the loop for it to guard).
   Test: P2-only pass 6 launches
4. D4 The verify die texts keep "a P0 or P1 is never capped" and, under REVIEW_CAP, "holds the merge below the cap": behaviour there is unchanged and threshold.test.sh:77-79, :103-108 pin them.
   Test: none, existing checks threshold.test.sh:77-79 and :103-108 pin the texts unchanged
5. D5 W27, W29 and W37 are host-only, and W35 is host-only but for its "new file" deletion (W table reasons); no plugin feature is added for them.
   Test: host-only items stay single
6. D6 The global CLAUDE.md template (templates/global-claude.md) is the owner's machine-wide file and keeps its code-exploration table and keep-list: the host cleanup changed project rules only.
   Test: none, the file is unchanged
7. D7 The relay's state is reordered only for printing; the file is never written. With no handoff heading the order is the file's.
   Test: no handoff starts at header
8. D8 Owner answer to Q1 (2026-11-04): A. `reviewPassCap` / `passCap` keeps its key and saved values and is retitled "Closing pass from", with the Setting text After (A) description in plugin.json and the setup skill.
   Test: none, no test reads the setting's title or description (Assumptions, settled); its behaviour is pinned by "P2-only pass 6 launches"
9. D9 Owner answer to Q2 (the owner's auto-answer delegate, citing an owner pick of 2026-10-30): yes to every line of Test edits -- the 2 deletions, the 5 edits and the comment-only rewording; they follow the removed cap and weaken no remaining check.
   Test: P2-only pass 6 launches
10. D10 Owner answer to Q3 (2026-11-04): yes, the six user-visible changes ship as listed. User-visible changes has seven bullets; the setup/settings bullet is D8's Setting text, and the other six are the ones Q3 approved.
   Test: none, each change is pinned by its cut's acceptance tests
11. D11 main-watch-report-wake.test.sh:101's fixture keeps its old REVIEW STOP wording: stop_next reads only the decision id from it (main-watch.sh:975), and editing the line needs a test-edit ruling the change does not need.
   Test: watcher REVIEW STOP names no pass number
12. D12 Owner answer to Q4 (2026-11-04): A. The owner-set round limit (`review-cap.sh <unit> <rounds>`, builder-codex-pass.sh:1217-1226) stays as the owner's per-unit brake; C1 keeps it and rewords only its comment; a unit without the file has no limit.
   Test: none, the code is unchanged and the existing review-cap.sh checks in 9 builder-codex-pass test files (decisions, closing, rebase, class-return among them) still run
13. D13 Owner answer to Q5 (the owner's auto-answer delegate, citing an owner pick of 2026-10-30): A, approve. C3 updates scripts/__tests__/merge-rules.test.sh to the new ids and counts (all 40 checks kept) and adds the matching 0.72.0 links in scripts/merge-rules.py, so a user who kept their own wording of an old rule keeps it.
   Test: none new, the existing 40 checks of scripts/__tests__/merge-rules.test.sh, re-pointed, pin the lineage (Claims to falsify: `40 passed, 0 failed`)

## Accepted failure modes

- A project whose saved passCap is large (this checkout: 99) gets its REVIEW STOP at that pass + 2, not pass 7; the owner may set it back (D8).
  Test: none, the anchor arithmetic is unchanged and threshold.test.sh:109 pins REVIEW STOP at REVIEW_CAP + 2
- A unit already stopped at a cap stop when the plugin updates no longer merges: its next `--verify` refuses the NO-GO and the Builder runs a fix round. No live cap-stop unit is known.
  Test: P2-only pass 6 launches

## Assumptions

- [settled] No test reads reviewPassCap's description text (helper search of scripts/__tests__ and hooks/__tests__, 2026-11-04; nearest: setup.test.sh:107-113 type and value).
- [settled] No main-watch or merge test pins a cap stop (rg 'cap stop|STOP \(cap|file one issue' over scripts/__tests__/main-watch-*.test.sh and merge-unit-local.test.sh: none asserting, 2026-11-04).
- [settled] The plugin has no rule-drift map file (rg -i 'rule.drift' over the repo: comments and tests only, 2026-11-04).
- [settled] No settings.json of the owner's saves fixerEffort (jq over ~/.claude/settings.json and the three Orca profile settings.json files: unset in each, 2026-11-04).

## User-visible changes

- Builder, before: a closing NO-GO with only P2 open at pass 5 or later printed `STOP (cap)` and merged with the findings filed; a later pass was refused. After: no such line; a fix round runs and the next pass launches; only a closing GO or a threshold stop merges.
- Builder and main, before: REVIEW STOP said "two passes past the cap". After: "at pass 7 or later" (the setting + 2).
- Main, before: main-watch could post "cap stop: file one issue per class, then hand merge". After: never.
- Setup and /plugin settings: Setting text (D8).
- Setup's Recommended set and Auto Setup, before: later fix rounds at high effort. After: medium (the owner's order, 2026-11-04).
- Relay, before: its saved state printed from the top, cut at 5000 bytes, an empty file printed an empty banner. After: the newest handoff section prints first, one warning line when the file is over 5000 bytes, an empty file prints nothing.
- Main, before: "End each turn with one status line", "Announce every worker", "do not report how often main restarts", "serena for symbols". After: no status-line rule, a worker is announced once at dispatch, restart counts may be reported, `rg` for symbols in main.
- Every pane, before: ask before building backward compatibility; tag every claim. After: no old-data support unless a live old record is known; tag only unverified claims.

## Question for the owner

None: answered as D8 (Q1), D9 (Q2), D10 (Q3), D12 (Q4) and D13 (Q5).

## Test edits

- delete scripts/__tests__/builder-codex-pass-cap-gate.test.sh: 9 checks on the refusal after a cap stop, which goes
- delete builder-codex-pass-threshold-cap.test.sh:48 and :94 (cap stop at 5, at 3); "P2-only pass 6 launches" replaces them
- edit builder-codex-pass-threshold-cap.test.sh:44-47: the cp fixture reaches :50-62 by a threshold stop; claims and texts kept
- edit builder-codex-pass-threshold.test.sh:138: still asserts the refusal, without the removed 'names no open P2' text
- edit brief-template.test.sh:101, :103: the new template sentences (two stop lines; REVIEW STOP at pass 7)
- edit agent-startup-context.test.sh:120: asserted the one-status-line rule the order removes; now asserts it is gone
- edit template-sections.test.sh:24: asserted the restart-report ban the order removes; now the new sentence
- comment-only rewording in seven test files (C1 Tests); no assertion touched
- edit merge-rules.test.sh:21, :28, :46, :58, :66-67, :71 (D13): the rule count and ids the rewording changes; every check kept, each pair's old anchor kept

## Setting text

- Before: "Review pass cap: 5 | 3 | 8 -- from this many passes, a closing NO-GO with no P0 or P1 ends the loop with its findings open".
- After (A): "Closing pass from: 5 | 3 | 8 -- from this many passes every pass is a closing pass; a P0 or P1 still open two passes later stops for the owner".

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- Cap lines in the 14 review-loop files: 51 (Claims review-loop rg, 2026-11-04); after C2, 0.
- Cap identifiers in the three loop scripts: 23 lines (Claims C1 rg, 2026-11-04); after C1, 0.
- This checkout's passCap: 99 (.claude/commandeck.json, 2026-11-04).
- Relay state share: 5000 bytes (agent-startup-context.sh:156).
- merge-rules.test.sh, planned wording: 8 of 40 fail; with C3's edits 40 pass (scratch copy, 2026-11-04).

## What can go wrong

| Case | Input or starting state | Expected | Test |
|---|---|---|---|
| P2 alone at the anchor | default passCap 5; pass 5 a closing NO-GO naming one P2, no P0/P1 | no STOP line; --verify refuses (ended NO-GO); pass 6 launches | P2-only pass 6 launches |
| State at exactly the share | relay state of exactly 5000 bytes | printed whole, no warning, no cut line | state at 5000 bytes no warning |
| Two handoffs, none newest | headings `## Handoff 11-02`, `## Handoff 11-03` | `## Handoff 11-03` prints first | last handoff first when none newest |
| Empty state | state file of 0 bytes | no state banner; hook exits 0 | empty state no banner |
| No handoff heading | header and `## Decided today` only | header first, file order | no handoff starts at header |
Bad input: the state file absent prints nothing, as today; empty is row 4; junk with no `## ` heading prints in file order, cut at 5000; a `## Handoff` line inside a code fence counts as a heading (accepted, the relay writes the file); trailing spaces on a heading still match; a quoted heading (`## "Handoff (newest)"`) matches on its words. passCap junk or 0 is refused by pp_review_loop as today (plugin-option.test.sh:57-59); an empty passCap reads as the default 5 (paths.sh:1155), as today; no new argument is parsed.

## Acceptance test

- test file path: scripts/__tests__/builder-codex-pass-threshold-cap.test.sh (P2-only pass 6 launches)
- test file path: scripts/__tests__/brief-template.test.sh (rule text carries no pass cap)
- test file path: scripts/__tests__/main-watch-report-wake.test.sh (watcher REVIEW STOP names no pass number)
- test file path: hooks/__tests__/agent-startup-context.test.sh (newest handoff first, one over-cap warning; no handoff starts at header; empty state no banner; state at 5000 bytes no warning; last handoff first when none newest; announce worker once, no status-line rule)
- test file path: scripts/__tests__/template-sections.test.sh (removed rules gone from templates; host-only items stay single)
- test file path: scripts/__tests__/plugin.test.sh (recommended fixer at medium)

Bugs caught: a pass still stopped or refused at the cap; a watcher note naming a wrong pass number; rule text naming a cap; a relay reading stale text before its newest handoff; an oversized state unnoticed; an empty banner; a removed rule back; a host-only rule copied twice.

## Break proofs

Break: none -- the unit adds no security check and no conditional write; it removes a stop and changes printed text

## Claims to falsify

- After C1, `rg -n 'cap_gate_reason|cappable_count|CAPPED|STOP \(cap\)|cap stop|CAP_LEVELS' scripts/builder-codex-pass.sh scripts/main-watch.sh scripts/merge-unit-local.sh` finds nothing.
- After C1, main-watch's REVIEW STOP note names no numeric pass threshold and no "cap" for any saved passCap.
- After C1, `--verify` exits non-zero for every NO-GO round, at any pass count.
- After C1, the `--verify` REVIEW STOP text (:945), the one main-watch consumes, matches its `REVIEW STOP:.*decision (review-stop-...);` parse.
- After C1, a `review` pass at or past REVIEW_CAP runs as `final`.
- After C2, `rg -n -i 'cap stop|STOP \(cap\)|past the cap|at the cap|the review cap|review pass cap|pass cap'` over the 14 review-loop files (C2 Produces) finds 0 lines (today 51).
- After C3, `rg -n 'one status line|how often main restarts|serena for symbols|Tag each claim|Ask before building backward' templates` finds nothing.
- After C3, `rg -n 'smallest change that FULLY' templates` finds one line, in global-rules.md.
- After C3, `bash scripts/__tests__/merge-rules.test.sh` prints `40 passed, 0 failed`.
- After C4, a relay state with no handoff heading prints as before for files under 5000 bytes.
- After C5, `jq -r .options.fixerEffort config/recommended.json` prints `medium`.
- After Release, `grep -c 'badge/version-0\.72\.0-.*alt="Version 0\.72\.0"' README.md` prints 1 and `bash scripts/__tests__/plugin.test.sh` passes its badge checks.

## Issue cases

- #661 Body 1 -- scripts/builder-codex-pass.sh -- P2-only pass 6 launches
- #661 Body 2 -- templates/global-rules.md -- removed rules gone from templates
- #661 Body 3 -- templates/global-rules.md -- removed rules gone from templates
- #661 Body 4 -- templates/global-rules.md -- removed rules gone from templates
- #661 Body 5 -- scripts/__tests__/template-sections.test.sh -- host-only items stay single
- #661 Body 6 -- templates/main-session.md -- announce worker once, no status-line rule
- #661 Body 7 -- scripts/__tests__/template-sections.test.sh -- host-only items stay single
- #661 Body 8 -- hooks/agent-startup-context.sh -- newest handoff first, one over-cap warning
- #661 Body 9 -- scripts/__tests__/template-sections.test.sh -- host-only items stay single
- #661 Body 10 -- templates/main-session.md -- removed rules gone from templates

## Done

- #661 Done: the owner updates the plugin and runs a build whose pass 5 ends NO-GO on a lone P2 -- no cap-stop line prints, pass 6 launches, the build merges only on a closing GO; main's, the relay's and every pane's rules show the new wording

## Progress notes

- #661: planned

## Facts

- REVIEW_CAP from passCap, default 5 -- scripts/builder-codex-pass.sh:26-36 (observed: 2026-11-04)
- REVIEW_CAP, cappable_count -- scripts/builder-codex-pass.sh:436-447 (observed: 2026-11-04)
- --verify REVIEW STOP, CAPPED, at-cap, dies -- scripts/builder-codex-pass.sh:941-964 (observed: 2026-11-04)
- Owner-set round limit -- scripts/builder-codex-pass.sh:1218-1226 (observed: 2026-11-04)
- Launch refusals lack decision id; cap_gate_reason -- scripts/builder-codex-pass.sh:1332-1375 (observed: 2026-11-04)
- review runs as final from REVIEW_CAP -- scripts/builder-codex-pass.sh:1403-1406 (observed: 2026-11-04)
- STOP (cap) branch -- scripts/builder-codex-pass.sh:2449-2458 (observed: 2026-11-04)
- stop_next reads the decision id -- scripts/main-watch.sh:962-980 (observed: 2026-11-04)
- passCap brief line -- scripts/builder-launch.sh:344-348 (observed: 2026-11-04)
- review-cap.sh writes it -- scripts/review-cap.sh:2-18 (observed: 2026-11-04)
- Watcher check -- scripts/__tests__/main-watch-report-wake.test.sh:98-104 (observed: 2026-11-04)
- Merge comments name the cap -- scripts/merge-unit-local.sh:373-408 (observed: 2026-11-04)
- Setup says pass cap -- scripts/setup.sh:158 (observed: 2026-11-04)
- Empty passCap reads as the default -- scripts/paths.sh:1155 (observed: 2026-11-04)
- Options from pluginConfigs -- scripts/paths.sh:1191-1196 (observed: 2026-11-04)
- Done has closing NO-GO at cap -- templates/global-rules.md:40-43 (observed: 2026-11-04)
- Ask before backward compatibility -- templates/global-rules.md:5-6 (observed: 2026-11-04)
- Tag each claim -- templates/global-rules.md:67-68 (observed: 2026-11-04)
- Map, smallest-change, alternatives -- templates/global-rules.md:163-176 (observed: 2026-11-04)
- README names the pass cap -- README.md:246 (observed: 2026-11-04)
- Badge 0.71.0 -- README.md:4 (observed: 2026-11-04)
- Badge matches manifest -- scripts/__tests__/plugin.test.sh:33-34 (observed: 2026-11-04)
- Template stop lines -- templates/_builder-brief-template.md:278-286 (observed: 2026-11-04)
- "or a cap stop" -- templates/main-rulings.md:15 (observed: 2026-11-04)
- reviewPassCap title; fixer default project -- .claude-plugin/plugin.json:66-72 (observed: 2026-11-04)
- Setup asks "Review pass cap" -- skills/setup/SKILL.md:272-279 (observed: 2026-11-04)
- passCap 99 here -- .claude/commandeck.json:5-7 (observed: 2026-11-04)
- serena; wake bullet -- templates/main-session.md:15-17 (observed: 2026-11-04)
- Status line; restart ban -- templates/main-session.md:30-38 (observed: 2026-11-04)
- Announce workers; lookup serena -- templates/main-session.md:131-154 (observed: 2026-11-04)
- Project keep-list -- templates/AGENT_STARTUP.md:71-77 (observed: 2026-11-04)
- Codex file: no keep-list -- templates/codex-instructions.md:1-17 (observed: 2026-11-04)
- Codex reads the startup file -- hooks/agent-startup-context.sh:127-128 (observed: 2026-11-04)
- Relay state cut at 5000 bytes -- hooks/agent-startup-context.sh:153-157 (observed: 2026-11-04)
- Rollout rule in the judge spec -- scripts/seat.sh:616-617 (observed: 2026-11-04)
- Status-line check -- hooks/__tests__/agent-startup-context.test.sh:120 (observed: 2026-11-04)
- Restart-ban row -- scripts/__tests__/template-sections.test.sh:24 (observed: 2026-11-04)
- Stop-line checks -- scripts/__tests__/brief-template.test.sh:101-103 (observed: 2026-11-04)
- cp fixture, cap checks -- scripts/__tests__/builder-codex-pass-threshold-cap.test.sh:44-100 (observed: 2026-11-04)
- Rule ids and counts pinned -- scripts/__tests__/merge-rules.test.sh:27-75 (observed: 2026-11-04)
- MADE_FROM lineage per release -- scripts/merge-rules.py:114-203 (observed: 2026-11-04)
- Fixer effort medium -- config/routing.json:65-68 (observed: 2026-11-04)
- Recommended fixer high -- config/recommended.json:12 (observed: 2026-11-04)
- Auto profile fixer medium -- config/auto-profile.json:7 (observed: 2026-11-04)
- Builder recommended check -- scripts/__tests__/plugin.test.sh:65-66 (observed: 2026-11-04)

## Plan change log

- 2026-11-04 first version.
- 2026-11-04 owner answer Q1 (A) recorded as D8; D2, C2, Steps, the failure-modes section and User-visible changes now cite D8 in place of Q1.
- 2026-11-04 owner answer Q2 (yes to all) recorded as D9; C1, C2, C3 Tests and Steps now cite D9 in place of Q2.
- 2026-11-04 owner answer Q3 (yes) recorded as D10.
- 2026-11-04 the Builder check before C1 is removed: Q1 and Q2 are answered (D8, D9), so it had nothing left to check.
- 2026-11-04 the Question for the owner section now reads "None: answered as D8 (Q1), D9 (Q2) and D10 (Q3)".
- 2026-11-04 judge P1 (round limit at builder-codex-pass.sh:1220): accepted as an owner call; Q4 added (pick A, keep), C1 gains the Builder check on Q4 and rewords the :1218-1219 comment; Facts cite :1218-1226 and review-cap.sh:2-18.
- 2026-11-04 judge P1 (cap text outside the edits): accepted; C2 adds global-rules.md:40-43, merge-unit-local.sh:373-377/:408/:544, README.md:246/:474 and setup.sh:158/:307/:381 (a further site the same rg found); C1's merge-unit-local consumer line corrected; W3 row, Steps and Planned size updated.
- 2026-11-04 judge P1 (W35 not wholly host-only): accepted; the host diff drops "new file" from the alternatives rule, so C3 drops "or a file" at global-rules.md:173-174; W35 row, D5, Issue case Body 4 and a claim updated.
- 2026-11-04 judge P1 (leak): accepted; owner names, the delegate's nickname and ruling ids removed from D8-D10 and this log.
- 2026-11-04 judge P2 (watcher number has no producer): accepted; main-watch's REVIEW STOP text names no pass number (it has no REVIEW_CAP), the pass script interpolates its own REVIEW_CAP; new test "watcher REVIEW STOP names no pass number" (New tests 11); D11 keeps the :101 fixture.
- 2026-11-04 judge P3 (claim rg matches bash-guardrails CAPPED): accepted; the C1 claim's rg is scoped to the three loop scripts; the limits section recounted with the scoped commands (51 and 23 lines).
- 2026-11-04 owner answer Q4 (A, keep review-cap.sh as the owner's per-unit brake) recorded as D12.
- 2026-11-04 the W3 row and C1's Keeps line cite D12 in place of "pending Q4" / "Q4 pick A".
- 2026-11-04 the Builder check before C1 on Q4 is removed: Q4 is answered (D12), so it had nothing left to check.
- 2026-11-04 the Question for the owner section now reads "None: answered as D8 (Q1), D9 (Q2), D10 (Q3) and D12 (Q4)".
- 2026-11-04 judge P1 (merge-rules.test.sh fails): accepted; confirmed on a scratch copy (8 of 40 fail). C3 adds merge-rules.py lineage and the test's id and count edits, every check kept (40 pass); Q5 asks for them; a Builder check before C3; Steps, Test edits, the limits section, Claims, Facts and Planned size (31 files, 482 lines) updated.
- 2026-11-04 judge P3 (watcher claims): accepted; the watcher claim says no numeric pass threshold, and the parse claim covers only the `--verify` text (:945) main-watch consumes.
- 2026-11-04 judge P3 (empty passCap): accepted; the Bad input line says an empty passCap reads as the default 5 (paths.sh:1155) and cites plugin-option.test.sh:57-59.
- 2026-11-04 owner addition (relayed by main): the recommended fixer effort goes high -> medium; C5 added (recommended.json:12, a plugin.test.sh check), the owner's saved value checked (none saved, nothing to write); Build order, New tests 12, Acceptance test, User-visible changes, Assumptions, Facts and Planned size (33 files, 488 lines) updated.
- 2026-11-04 owner answer Q5 (A, approve the merge-rules lineage and test id edits) recorded as D13.
- 2026-11-04 C3's Lineage and Tests lines, Steps and Test edits cite D13 in place of "Q5" / "Q5, pending".
- 2026-11-04 the Builder check before C3 on Q5 is removed: Q5 is answered (D13), so it had nothing left to check.
- 2026-11-04 the Question for the owner section now reads "None: answered as D8 (Q1), D9 (Q2), D10 (Q3), D12 (Q4) and D13 (Q5)".
- 2026-11-04 judge P1 (README version badge left at 0.71.0): accepted; Release adds README.md:4's image URL and alt text to 0.72.0, its consumer line names plugin.test.sh:33-35 (assertion unchanged); Steps, Claims to falsify, Facts and Planned size (33 files, 490 lines; README already counted) updated.
- 2026-11-04 Builder: three log lines above name the limits and failure-modes sections in prose, not by their heading text, as the pass's heading check asks; no limit or rule changed.

## Follow-ups

- Host, after the merge (main, outside this unit): mark W27, W29, W37 and W35's 200-line check host-only in the host's drift map with the W table reasons, and re-sync the host sections this unit ports.
- Host drift lines that predate this cleanup (unmapped brief-template and routing.json sections, and the changed brief-template, reviewer-tools and routing.json sections): not ported here.

## Verification

- Per cut: `bash scripts/run-shell-tests.sh --changed` on the PC; before the merge, the full shell suite on the PC; `bash ci/version-check.sh main`.

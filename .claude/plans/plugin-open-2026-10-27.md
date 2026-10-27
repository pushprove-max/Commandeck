# Plan: plugin-open-2026-10-27: every open plugin issue, one unit

Owner's words: Order: the owner, 2026-10-27: "build ALL open Commandeck issues in ONE unit". ONE unit, no split, whatever the size caps say. #399 and #401 shipped in 0.52.1 and are closed; this unit builds the rest.

The rest is #402, #400 and #386 (`gh issue list -R pushprove-max/Commandeck --state open`, 2026-10-27: exactly these
three). Every requirement below traces to one of their issue texts or to the plan spec's section for it; nothing else
is added.

Closes: #402, #400, #386

- Planned size: 20 files, 292 changed lines

Tier: Standard. LOCAL merge only. Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no
test-timeout raise. Tests run on the PC. No red or mutation proofs except the break runs this plan's `Break:` lines
name: each is run red before pass 1 and recorded in the evidence file as `Mutation-verified: <test file> -- <check
label>: RED, <how>`. One unit, no split.

Helper subagents: hand work to helpers on the smallest model that can do it, and name the model on every call:
`general-purpose` on Sonnet for reading code, test triage and mechanical edits, `Explore` on Haiku for search. The
Builder brief carries this line.

Sources of every port, from the host's local main: `853980ed` (host 3219 = #402), the squash commit `80c5b6a2`
(host 3215 = #398, 3216 = #397, 3218 = #399, the halves of #400), host `paths.sh` at HEAD for the `multi_agent`
word (#400 item 4), and `fea64e3e` (host 3205 = #386). No later host commit touches any of these files
(`git log 80c5b6a2^..HEAD -- <files>` and `git log -1 -- <file>` for each, 2026-10-27). Host hunks are cited as
`host <file>:<line>` at HEAD.

Timed checks: `scripts/__tests__/codex-ask.test.sh` ("a timeout fails loudly" at :81-83 and "a Codex that ignores
TERM is killed after the grace" at :84-86; its heavy case "a real Codex refuses a write" at :93 stays last),
`scripts/__tests__/seat-launch.test.sh` (`COMMANDECK_SEAT_SETTLE_SECONDS=0` launches at :24, :38, :60, :183-190). This
unit adds no heavy fixture to any file. The light new cases in these two files (C1, C2) go after each file's last
timed check, and in `codex-ask.test.sh` before the heavy real-Codex case. One new time-bound check: "a typecheck past
its time limit names the check that gave no result" (C5, `builder-codex-pass-rebase.test.sh`, exit within 20 s).
That file has no other time-bound check (`grep -n 'timeout [0-9]\|timeout --\|^# timeout\|seq [0-9]*); do'` is
empty, 2026-10-27), and the case goes after the file's existing typecheck cases (:58-71).

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

- L1 (#386). The plugin runs no project command at Stop. `jq -r '.hooks.Stop[].hooks[].command' hooks/hooks.json`
  lists four hooks (context-clear-stop, ask-stop-records-decision, cos-inbox-waiter-stop, opus-orchestrator-autonomy
  `--stop`). No SubagentStop is registered. The Codex Stop entry (`templates/codex-hooks.json:6`, 120 s) re-routes to
  the same four. `rg -n 'npm|npx|tsc|vitest|testCommand|run-shell-tests|lint'` over those four files finds a
  self-test comment only (`hooks/cos-inbox-waiter-stop.sh:11`). All of this was run on 2026-10-27. So the host's
  two Stop-hook hunks (host `typecheck.sh`, host `tier1-stop.sh`) have no Stop twin, and no Stop hook is invented
  (Decision 13). #386 lands on the one check that runs before a closing pass with no bound: the closing-pass typecheck.
- L2 (#386). Cache seeding helps only a typecheck that writes a `.tsbuildinfo` file inside the checkout
  (`tsc --incremental`, `composite`, `tsc -b`). Setup's detected default `npx tsc --noEmit` writes none, so it gets
  no gain and no change. Measured on the Mac on 2026-10-27 with tsc 6.0.3 on this repository's own `tsconfig.json`
  (`tsc --noEmit --incremental --tsBuildInfoFile .cache/tc.tsbuildinfo -p .`):
  - cold: 0.91 s
  - warm: 0.28 s
  - seeded from a sibling folder at the same depth: 0.30 s, three runs
  - seeded from a checkout at another folder depth: 0.86 s, no gain (A4)
- L3 (#386). The typecheck's time limit is 300 s. The slowest typecheck in #386's issue text was 152 s
  (2026-10-26). A typecheck that runs past 300 s refuses the closing pass with a no-result line. The Builder reruns
  the pass, and the rerun's cache is warm.
- L4 (#386). The seeding scan walks each sibling worktree (pruning `node_modules` and `.git`), so its cost grows
  with the sibling trees. Today there is 1 worktree under this project's workspaces folder, and the scan took 0.00 s
  (`/usr/bin/time -p find <workspaces>/*/ \( -name node_modules -o -name .git \) -prune -o -name '*.tsbuildinfo'
  -type f -print`, 2026-10-27).
- L5 (#400). `--disable multi_agent` rides the seat launch words only, as on the host (host `paths.sh:637-639`; host
  `git grep multi_agent` outside tests finds that line alone, 2026-10-27). The plugin's Codex review passes start
  through the companion broker (`scripts/builder-codex-pass.sh:1634`), not the launch words, so the switch reaches
  `plan-judge-sol` on Codex and any `codex-reviewer` launched as a seat. The host's passes use the same broker path
  (host `builder-codex-pass.sh:1312-1318`).

## Main answers

- The seeder creates the seed's parent folder (`mkdir -p`) before the temp-file copy; any seeding failure falls back to a cold compile and never fails the pass. The fresh worktree with no parent folder is tested.
- The comment-only exemption covers lines whose code part is only a comment; an inline JSX comment inside a real element stays refused. The exemption is tested with comment-only fixtures, and `<div>{/* ... */}</div>` is a refused test.
- plan-check's refusal exits the script nonzero: the candidate loop runs in the calling shell, not behind a pipe. The `Coming soon banner` line is tested to exit nonzero (#400).
- The codex-ask worktree refusal runs after `record`, `fail` and their inputs are defined, and writes the existing-format failure row; its test asserts that row.
- The host's case-insensitive model-family matching is ported: a full model id naming Sonnet or Haiku is kept, as #400 asks the plugin to match the host. `claude-haiku-4-5` is tested.
- The family match skips helper-map entries that are absent (null) before lowercasing, so a partial map such as `{"general-purpose":"sonnet"}` still rewrites a `general-purpose` call naming `opus` to Sonnet. The partial map is tested.
- Every added build, merge or review step (cache discovery, the typecheck timeout gate, the B1 build check) has a `Catches:` line naming the failure it stops.

## Question for the owner

None.

## 1. Item map (what exists, what the host built, where it lands, the test)

| Issue | Host hunks ported | Plugin today (file:line) | Lands at | Cut |
|---|---|---|---|---|
| #402 | host `main-watch.sh` `helper_out` (bg count first, then the event log); host `main-watch.test.sh` +17 (three bg cases) | already built in 35c05ca: `scripts/main-watch.sh:255-267`, which holds on `PP_SESSION_BG > 0` within `HOLD_S` (:54, 3600 s) of the record's last write; test `scripts/__tests__/main-watch-helper-hold.test.sh:76-93`; release note `CHANGELOG.md:45` (0.52.0). 35c05ca's merge message did not close the issue | nothing; `Closes #402` | C6 |
| #400 / #398 | host `placeholder-ui.sh:11` (`under construction`), `:16-40` (`_pp_code`: comment lines are not placeholder UI), host `plan-check.sh:87-106` (refuses, skips fences, `Placeholder:` lines and issue cites) | `hooks/lib/screen-code.sh:42` (no `under construction`); tripwire copy loop `hooks/edit-content-tripwires.sh:291-294` and merge `scripts/merge-unit-local.sh:290-301` screen whole lines, comments too; `scripts/plan-check.sh:48-60` flags and passes | `hooks/lib/screen-code.sh:42` and after `:66`; `hooks/edit-content-tripwires.sh:292`; `scripts/merge-unit-local.sh:290-301`; `scripts/plan-check.sh:48-60` | C4 |
| #400 / #397 | host `agent-model-guard.sh:33-34` (a pane's general-purpose whose named model, lower-cased, contains `sonnet` or `haiku` keeps it) | `hooks/agent-model-guard.sh:34` rewrites anything but the exact name of the type's own map model | `hooks/agent-model-guard.sh:34` | C3 |
| #400 / #399 | host `codex-ask.sh:39-47` (fixed `/tmp` template, refuses a folder inside any worktree), `:58` (`--ignore-rules`) | `scripts/codex-ask.sh:32` (`mktemp -d` honours TMPDIR, no check), `:41` (no `--ignore-rules`) | `scripts/codex-ask.sh:32-33`, `:41` | C2 |
| #400 item 4 | host `paths.sh:637-639` (`--disable multi_agent` for `.agent == "codex" and .reviewer`) | `scripts/paths.sh:889` (`plugins:` word, `--disable plugins` only) | `scripts/paths.sh:889` | C1 |
| #386 | host `typecheck.sh` `seed_info` (newest same-name buildinfo of a sibling checkout, temp file then rename, any failure compiles cold); host `tier1-stop.sh` "no result from:" wording | `scripts/builder-codex-pass.sh:1368-1378` `typecheck_green`: no time bound (:1374), a killed run reads as red, no seeding | `scripts/builder-codex-pass.sh:1363-1378` | C5 |

### #400: every behaviour difference, and the call

| Pair | Difference (host vs plugin) | Call |
|---|---|---|
| #398 | `under construction` is placeholder copy on the host; the plugin also has its `later release` phrase, the host does not | port the phrase, keep the plugin's extra (Decision 3) |
| #398 | host skips comment lines (`//`, `/*`, `*`, `{/*`) and screens code after a closed leading comment; the plugin screens whole lines | port (Decision 4) |
| #398 | host plan-check refuses a placeholder line outside a fence that is not a `Placeholder:` line and cites no issue; the plugin flags every such line and passes | port (Decision 5) |
| #398 | approval syntax (host quoted `Placeholder:` and `Disabled:`; plugin `Placeholder: <file> \| <line> \| <why>`); approvals read from the fork-point plan (host) or local main's plan and rulings (plugin); host hardcodes `web/src`, plugin has `screenPaths`; edit hook strict-tier in the plugin; per-line approval counts and a 20-entry list in the plugin; no pass line in the plugin | keep the plugin's (Decision 6) |
| #398 | host's tag scanner reads multi-line tags and a continuation `disabled` line; the plugin's single-line fixed pattern states those misses | keep the plugin's (Decision 6) |
| #397 | host keeps a pane's general-purpose call naming sonnet or haiku; the plugin rewrites haiku to sonnet | port (Decision 7) |
| #397 | host matches the model family case-insensitively anywhere in the name (`claude-haiku-4-5`, `Sonnet` are kept); the plugin compares exact names, so a full model id is rewritten | port (Decision 7) |
| #397 | models live in routing (plugin) vs hardcoded (host); plugin enforces debugger in panes, host does not; pane detection by seat (plugin) vs env markers (host) | keep the plugin's (Decision 8) |
| #399 | host passes `--ignore-rules`; plugin does not | port (Decision 9) |
| #399 | host's working folder is a fixed `/tmp` template and is refused when inside any worktree; plugin's honours TMPDIR | port (Decision 10) |
| #399 | timeout knob (option vs env), TERM then KILL (plugin), 6000-byte vs 8000-char cut, answering model from Codex's header (plugin) vs the configured one, helper-pane gate vs reviewer-only refusal, metrics row shape | keep the plugin's (Decision 11) |
| item 4 | Codex reviewer and judge seats launch with `--disable multi_agent` on the host; the plugin's do not | port (Decision 12) |

### #386: what runs at Stop or before a closing pass today

| Check | When | Bound | On timeout |
|---|---|---|---|
| four Stop hooks (`hooks/hooks.json:100-107`) | every Stop | none | run no project command (L1) |
| rebase tests (`scripts/builder-codex-pass.sh:1332-1362`) | closing pass, main moved | per file (`scripts/run-shell-tests.sh:167`, `:204`) | named: `FAIL <file> ... HUNG past <n>s` (`run-shell-tests.sh:182`), listed by the die at `builder-codex-pass.sh:1359` |
| typecheck (`scripts/builder-codex-pass.sh:1368-1378`) | closing pass, `typecheckCommand` set | **none** | a hang blocks the pass; a killed run reads "red" with no timeout wording: **the gap** |
| full suite (`scripts/builder-codex-pass.sh:1395-1415`) | before any reviewer, `testCommand` set | 3600 s (:1405) | named: `R=timeout` (:1406), `SUITE_RED` forces NO-GO (:1414) |
| post-fix checks (`scripts/post-fix-checks.sh:40`, `:66-69`) | after a fix round | 540 s | named: `post-fix: <name> timed out after <n>s` |

## 2. Cuts (build order)

Each cut lists what it changes, what it Produces and Consumes, the existing consumers of any contract it changes, its
size (changed lines: code, tests and docs), its acceptance tests and its `Break:` lines. A "flip" is an existing check
whose expected value changes.

Shared-file edit order: `docs/configuration.md` C1, C2, C3; `docs/review-loop.md` C4, C5; `CHANGELOG.md` and
`.claude-plugin/plugin.json` C6 last.

### C1 -- #400 item 4: Codex reviewer and judge seats start no sub-agents (~12 lines, 3 files)

1. `scripts/paths.sh:889`: the `plugins` word becomes the host's two-term form, with the host's comment above it:
   ```
   # Reviewer and judge seats start no helpers: a Codex one loses sub-agents here, a Claude one denies Agent in tools.
   plugins: ((if .disablePlugins then ["--disable", "plugins"] else [] end)
     + (if .agent == "codex" and .reviewer then ["--disable", "multi_agent"] else [] end)),
   ```
   The resolved seat has `.agent` and `.reviewer` when the words are built (A6).
2. `docs/configuration.md` helpers paragraph (:44-51): one sentence. Codex judge and reviewer seats launch with
   sub-agents off, and Claude ones have `Agent` denied.

Produces: a `--disable multi_agent` pair in the launch command of every seat whose route has `agent: codex` and
`reviewer: true`. Consumes: the codex template's `{plugins}` slot (`config/routing.json` `launch.templates.codex`).
Consumers of the changed contract (the `words` output): `pp_route_json` / `pp_route` `RT_CMD` (`scripts/paths.sh:902`,
`:1276-1280`), read by `scripts/seat.sh:279` (the launch) and by the seat record's `cmd=` line. No consumer parses
the words by position.

Acceptance tests (`scripts/__tests__/seat-launch.test.sh`, in the `for j in sol:planJudgeSol` loop at :124-136):
- "plan-judge-sol on codex launches with multi_agent off" (its record's `cmd=` has `--disable multi_agent` once)
- "plan-judge-sol on claude has no multi_agent word" (count 0)
- "a Codex seat that is not a reviewer keeps multi_agent" (A7 settles how to route one)

Break: scripts/__tests__/seat-launch.test.sh -- plan-judge-sol on codex launches with multi_agent off -- scripts/paths.sh the multi_agent term of the plugins word

### C2 -- #400 / #399: the Codex helper ignores rules files and never runs inside a worktree (~42 lines, 3 files)

0. `scripts/codex-ask.sh` order first (F4): `record` and `fail` (today :48-59) move up to just after `ROWS=` (:31),
   unchanged, preceded by their inputs' starting values: `MODEL= ELAPSED=0 BYTES=0
   START=$(date -u +%Y-%m-%dT%H:%M:%SZ)`. So every exit from `WORK=` on can write the existing-format row (`model`
   null, `secs` 0, `bytes` 0). The run's own `START=... T0=$SECONDS RC=0` line (:38) and the `ELAPSED`, `MODEL`,
   `BYTES` reads after it (:42-45) stay where they are and overwrite the starting values. The mktemp failure at :32
   becomes `fail failed "FAILED: cannot make a temp folder"`: today it exits 1 with no row, against the header's
   "Every call, failed or not, is one row" (:5-6).
1. `scripts/codex-ask.sh:32`: `WORK=$(mktemp -d /tmp/commandeck-codex-ask.XXXXXX)`, so an inherited TMPDIR cannot
   choose the folder. The trap that removes `WORK` (:33) stays right after it. Then the host's check: resolve `WORK`
   with `pwd -P`. For `$WT` and each `worktree` line of `git worktree list --porcelain`, each resolved with `pwd -P`,
   the call fails when `WORK` equals the tree or is inside it:
   `fail failed "FAILED: working folder <dir> is inside <tree>; Codex would load that tree's config"`. That writes one
   row with outcome `failed`, prints `codex-ask: FAILED: ...`, exits 1, and no Codex runs.
2. `scripts/codex-ask.sh:41`: `--ignore-rules` after `--skip-git-repo-check` (`codex exec --help` lists it on
   codex-cli 0.164.0, A8). The comment at :40 says rules files are not loaded.
3. `docs/configuration.md:53-62` (Codex helper): the folder is under `/tmp` and outside every worktree, and no rules
   files are loaded.

Produces: the working-folder refusal (exit 1, a `FAILED:` line). Consumes: `git worktree list --porcelain`. Consumers
of a changed contract: none. The answer, header, exit codes and metrics row shape are unchanged, and a refusal is a
`failed` row like any other `FAILED:` (the existing failure path at :65-70). The rows' readers are the
operator (`docs/configuration.md:60`) and the build review (`codex_helpers_for` in
`skills/worktreereview/scripts/collect.py`, which reads a null model as none; pass 1 found it, the earlier search
left `skills/` out), so the two new `failed` rows change no consumer. The metrics file is changed state: Data design.

Acceptance tests (`scripts/__tests__/codex-ask.test.sh`, after :86, before the real-Codex case):
- "the call runs read-only outside the repository" (flip-free extension: its argv check at :54 also counts
  `--ignore-rules` = 1)
- "an inherited TMPDIR inside the repository is ignored" (`TMPDIR=$W/tmpx`: rc 0, the stub's `cwd:` is under
  `/tmp` or `/private/tmp`, not under `$W`)
- "a working folder inside a worktree is refused" (a `mktemp` stub first on PATH that makes and prints `$W/inside`:
  rc 1, the `is inside` line, no `cwd:` row in the stub log, and one metrics row: `row length` = 1,
  `.[0].outcome` = `failed`, `.[0].model` = `null`)

Break: scripts/__tests__/codex-ask.test.sh -- an inherited TMPDIR inside the repository is ignored -- scripts/codex-ask.sh the fixed /tmp template of mktemp (replaced by a bare mktemp -d)
Break: scripts/__tests__/codex-ask.test.sh -- a working folder inside a worktree is refused -- scripts/codex-ask.sh the inside-a-worktree refusal
Break: scripts/__tests__/codex-ask.test.sh -- a working folder inside a worktree is refused -- scripts/codex-ask.sh the record call of the refusal (fail replaced by a bare echo and exit 1)
Break: scripts/__tests__/codex-ask.test.sh -- the call runs read-only outside the repository -- scripts/codex-ask.sh the --ignore-rules word

### C3 -- #400 / #397: a helper may run on the search model, named in any case or as a full id (~20 lines, 4 files)

1. `hooks/agent-model-guard.sh:34`: the enforcement test keeps a call whose named model, lower-cased, contains the
   type's own map model or the search helper's model, both lower-cased (the host's family match, `test("sonnet|haiku")`
   on `ascii_downcase`, read from the map instead of hardcoded):
   ```
   | (($in.model // "") | ascii_downcase) as $n
   | ([$h[$t] // empty, $h.Explore // empty] | map(ascii_downcase) | any(. as $f | $n | contains($f))) as $kept
   | ($pane == "1" and ($h | has($t)) and ($kept | not)) as $enforce
   ```
   Explore's two terms are the same model, so an Explore call naming anything but a haiku-family name is still
   rewritten. General-purpose and debugger calls naming `haiku`, `Haiku`, `claude-haiku-4-5` or `claude-sonnet-5-5`
   keep it. Naming anything else (`opus`, or no model) in a pane still runs as the type's map model, as today. The
   header comment (:3-14) gains one line saying so. Both map terms drop out when absent (`// empty`) before
   `ascii_downcase`: `paths.sh:736` accepts a partial map, and `ascii_downcase` on null errors into the hook's fallback
   (:44), which keeps the named model. Checked 2026-10-27 with `jq` on `{"general-purpose":"sonnet"}`: the plan's first
   form printed `explode input must be a string`; with `// empty`, `opus` gave false (rewritten), `Sonnet` true (kept).
2. `docs/configuration.md:44-51` and `docs/hooks.md:19`: a helper pane's general-purpose call may name the search
   model.

Produces: a pass-through for a call that names the search model. Consumes: `roles.builder.helpers.Explore`.
Consumers of a changed contract: none. The hook's output shape is unchanged; it prints nothing for the call.

Acceptance tests (`hooks/__tests__/agent-model-guard.test.sh`, beside the Builder cases at :69-72):
- "a Builder's general-purpose call naming haiku keeps Haiku" (no output)
- "a Builder's general-purpose call naming claude-haiku-4-5 keeps it" (the judge's input
  `{"subagent_type":"general-purpose","model":"claude-haiku-4-5"}`: no output)
- "a Builder's Explore naming claude-sonnet-5-5 runs as Haiku" (`updatedInput.model` = `haiku`)
- "a Builder's general-purpose call naming opus runs as Sonnet" (existing, unchanged)
- "a Builder's Explore naming sonnet runs as Haiku" (existing :71, unchanged)
- "a partial helper map still runs a general-purpose call naming opus as Sonnet" (a `$TMPD` overlay as at :97 with
  `.roles.builder.helpers = {"general-purpose": "sonnet"}`, `paneas x "$GP_OPUS" COMMANDECK_BUILDER=1
  COMMANDECK_ROUTING=...`: `sonnet`, not `none`)

Break: hooks/__tests__/agent-model-guard.test.sh -- a Builder's general-purpose call naming haiku keeps Haiku -- hooks/agent-model-guard.sh the search-model term of $kept
Break: hooks/__tests__/agent-model-guard.test.sh -- a Builder's general-purpose call naming claude-haiku-4-5 keeps it -- hooks/agent-model-guard.sh the contains family match of $kept (replaced by an exact == comparison)
Break: hooks/__tests__/agent-model-guard.test.sh -- a partial helper map still runs a general-purpose call naming opus as Sonnet -- hooks/agent-model-guard.sh the `// empty` on `$h.Explore` in $kept (removed)

### C4 -- #400 / #398: one more phrase, comment lines are not placeholder UI, plan-check refuses (~110 lines, 9 files)

1. `hooks/lib/screen-code.sh:42`: `PLACEHOLDER_COPY` gains `|under construction` (#400). The plugin's `in a later
   release` stays.
2. `hooks/lib/screen-code.sh`, after `always_disabled_lines` (:66): `screen_code_part <line>` prints the code on a
   source line, the host's `_pp_code` (host `placeholder-ui.sh:27-40`) as a printing function:
   ```
   _SC_COMMENT_RE='^[[:space:]]*(//|/\*|\*|\{/\*)'
   screen_code_part() { # <line>
     local c=${1}
     while [[ $c =~ $_SC_COMMENT_RE ]]; do
       if [[ $c =~ ^[[:space:]]*// || $c != *'*/'* ]]; then return 0; fi
       c=${c#*'*/'}; c=${c#"${c%%[![:space:]]*}"}; c=${c#\}}
     done
     printf '%s' "$c"
   }
   ```
   A comment line prints nothing. A leading comment that closes on the line gives way to the code after it. A `//`
   comment never closes. A trailing comment stays screened. `always_disabled_lines` itself is unchanged: it judges each
   line alone (its comment at :49), so a caller may run it on one line's code part. The ceiling comment at :50-53 is
   updated: a control spelled in a comment-only line is no longer refused.
3. `hooks/edit-content-tripwires.sh:292`: the copy test reads `screen_code_part "$_l"`. The approval still matches the
   complete line `$_l`.
4. `scripts/merge-unit-local.sh:290-301`: per added line, `c=$(screen_code_part "$t")`. The copy occurrences come
   from `$c`, and the disabled count is `always_disabled_lines <<<"$c" | wc -l` when `$c` holds `disabled`, else 0.
   This replaces the whole-file read of the tip (`dis`, :291) and the `grep -cx "$num"` against it; per line it is the
   same result (each line is judged alone). The comment at :280-283 follows. The approval count still uses the
   complete line `$t`.
5. `scripts/plan-check.sh:48-60`: `flag_placeholders` becomes `refuse_placeholders`. The candidate lines are found
   in one pass, as now: `grep -inE "$PLACEHOLDER_COPY"` plus `always_disabled_lines`. The fenced line numbers, fence
   lines included, come from one awk (`/^```/ { f = !f; print NR; next } f { print NR }`, the same fence rule as the
   facts awk at :73). The first candidate that is not fenced, is not a `Placeholder:` line
   (`^[[:space:]]*(- )?Placeholder: `), and cites no issue (`#[0-9]+`) is refused through the script's own `refuse`
   (:20): `REFUSED: <label> line <n> describes placeholder UI: plan its removal, approve it on a Placeholder: line, or
   cite the issue that tracks it (#<n>)`, exit 2. The loop must run in the calling shell (F3). Today's
   `{ ...; } | sort -nu | while ...` (:54) runs the loop in a pipeline subshell, where `refuse`'s `exit 2` ends only
   the subshell and the script goes on to print `size` and exit 0. So the numbers are gathered first and the loop
   reads a variable:
   ```
   cands=$({ grep -inE "$PLACEHOLDER_COPY" <<<"${2}" | cut -d: -f1; always_disabled_lines <<<"${2}"; } | sort -nu)
   for n in $cands; do
     ...skip fenced, Placeholder: and #<n> lines...
     refuse "${1} line $n describes placeholder UI: ..."
   done
   ```
   Both callers (:59-60) stay plain calls, not in a pipe or `$(...)`. The header comment (:4-11) and the comment at
   :48-50 follow.
6. Docs: `docs/hooks.md:48` (comment lines are not screened; the phrase list), `docs/review-loop.md:54-57` (a plan or
   batch line that describes placeholder UI is refused unless fenced, approved or citing an issue).

Builder check B1 before item 5 (#400), after item 1: `rg -n -i "$(bash -c '. hooks/lib/screen-code.sh; printf %s
"$PLACEHOLDER_COPY"')" scripts/__tests__ hooks/__tests__ templates` and `rg -n 'FLAG: |flagged' scripts/seat.sh
templates docs`.
For each fixture fed to `plan-check.sh` (directly, or through `builder-launch.sh` or `seat.sh launch`) that the
refusal now stops, give the line a cite or fence when the case is not about placeholders, or list it as a flip below
when it is. Any prompt or doc line that says such lines are flagged is reworded to refused. Expected: only the three
flips below (2026-10-27 run: `builder-launch-resume-launch-line.test.sh` is the only plan-check fixture file with a
match).
Catches: a plan or batch fixture in another test file that holds placeholder copy for an unrelated reason, which the
new refusal would turn red at `run-shell-tests.sh --changed main` with no flip listed for it; and a prompt or doc
line that still tells a seat such lines are "flagged" and launch anyway.

Produces: `screen_code_part` (one caller each in the tripwire and the merge) and the plan-check refusal. Consumes:
`PLACEHOLDER_COPY` and `always_disabled_lines` (unchanged contracts). Consumers of changed contracts:
- `PLACEHOLDER_COPY` gains a phrase. Its readers are the tripwire (:292), the merge (:298) and plan-check (:53).
- plan-check's exit: refusal now exits 2 where the flag exited 0. Its callers are `scripts/builder-launch.sh:86` and
  `:110-132` (stop on exit 2) and `scripts/seat.sh` before a judge launch (stops on exit 2). Neither parses `FLAG:`
  (`rg -n 'FLAG' scripts/builder-launch.sh scripts/seat.sh` is empty, 2026-10-27).

Acceptance tests:
- `hooks/__tests__/edit-content-tripwires.test.sh` (after :142):
  - "under construction copy in screen code is refused" (#400)
  - "a comment line in screen code is not placeholder copy" (strict hooks, Edit of `web/src/X.tsx`; the text is in A9)
  - "copy after a closed JSX comment is refused"
- `scripts/__tests__/merge-unit-local-screens.test.sh`:
  - "placeholder copy and a disabled control in a comment-only line merge" (comment-only lines only: the file's own
    `ORDER` line at :151, `// Example: <Button disabled>Export</Button>` (#400), and `{/* Coming soon: <Button
    disabled>Export</Button> */}`, added to a screen file with a screenshot row: merge, no entry)
  - "an inline JSX comment inside a real element is still refused" (the `ORDER` line at :152, `<div>{/* Example:
    <Button disabled>Export</Button> */}</div>` (#400), added alone to a screen file with a screenshot row: step 1 refuses
    with one `disabled` entry. Its code part starts with `<div>`, so `screen_code_part` keeps the whole line and the
    unchanged scanner counts it)
  - existing cases unchanged; the scanner case at :145-160 tests `always_disabled_lines` alone, which is unchanged
- `scripts/__tests__/builder-launch-resume-launch-line.test.sh` (:116-124):
  - flip :118 "a plan that describes placeholder UI as context is flagged and still launches" becomes "a plan that
    describes placeholder UI as context is refused and launches nothing" (exit 2, the `REFUSED:` line naming
    `.claude/plans/u31.md line 3`, no `launch builder u31`)
  - flip :121 "a batch line naming a literal disabled control is flagged" becomes "a batch line naming a literal
    disabled control is refused"
  - flip :124 "a plan's Placeholder line is not flagged" becomes "a plan's Placeholder line passes" (exit 0, no
    `REFUSED:`)
  - new: "a fenced or issue-citing placeholder line passes" (the same plan line inside a fence, and again outside
    one with `(#12)` on it: exit 0 both)
  - new: "plan-check alone exits 2 on a placeholder context line" (`bash scripts/plan-check.sh` run directly on u31's
    plan, the judge's `The export page shows a Coming soon banner today.` (#400), with no batch: rc 2, one `REFUSED:` line on
    stderr, no `size ` line on stdout)

Break: hooks/__tests__/edit-content-tripwires.test.sh -- under construction copy in screen code is refused -- hooks/lib/screen-code.sh the under construction arm of PLACEHOLDER_COPY (#400)
Break: hooks/__tests__/edit-content-tripwires.test.sh -- a comment line in screen code is not placeholder copy -- hooks/edit-content-tripwires.sh the screen_code_part call (replaced by the whole line)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- placeholder copy and a disabled control in a comment-only line merge -- scripts/merge-unit-local.sh the screen_code_part call (replaced by the whole line)
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- an inline JSX comment inside a real element is still refused -- hooks/lib/screen-code.sh the start anchor of _SC_COMMENT_RE (dropped, so any line holding {/* reads as a comment)
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- a plan that describes placeholder UI as context is refused and launches nothing -- scripts/plan-check.sh the refuse in refuse_placeholders (replaced by the old FLAG echo)
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- a fenced or issue-citing placeholder line passes -- scripts/plan-check.sh the fence and issue-cite skips
Break: scripts/__tests__/builder-launch-resume-launch-line.test.sh -- plan-check alone exits 2 on a placeholder context line -- scripts/plan-check.sh the candidate loop in the calling shell (put back behind a `| while` pipe)

### C5 -- #386: the closing-pass typecheck is seeded warm and bounded, and a timeout names the check (~80 lines, 3 files)

1. `scripts/builder-codex-pass.sh`, before `typecheck_green` (:1363): `seed_typecheck_cache`, a port of host
   `seed_info` adapted to an opaque command. The host knows its one buildinfo path; the plugin does not, so it finds
   them:
   - Candidates: every `*.tsbuildinfo` file under each sibling of `$WT` (the folders `"${WT%/*}"/*/` but `$WT`,
     where `WT=$PP_WORKSPACES/$UNIT`, :927), found with
     `find . \( -name node_modules -o -name .git \) -prune -o -name '*.tsbuildinfo' -type f -print` in each sibling,
     paths taken relative to it and deduplicated.
   - For each relative path: skip it when `$WT/<rel>` exists, and skip it unless `git -C "$WT" check-ignore -q --
     <rel>` (never a tracked or unignored file). The source is the newest of the siblings' copies (`-nt`). Create the
     parent folder first, as the host does (host `typecheck.sh:134`): `mkdir -p "$(dirname "$WT/<rel>")"`, so a fresh
     worktree with no `.cache/` takes the seed (F1). Then copy it to `<rel>.$$`, date the copy 1980
     (`touch -t 198001010000`, so `tsc -b` checks every source against it, pass 1) and `mv -f` it into place:
     `{ mkdir -p ... && cp ... && mv -f ...; } 2>/dev/null || rm -f "$WT/<rel>.$$"`. Any failure (mkdir, copy or
     rename) removes the temp file and leaves the path absent, which is a cold compile. A folder made before a failed
     copy stays, empty and ignored. No associative arrays (Bash 3.2).
   - Prints `typecheck cache: seeded <n> file(s) from the worktrees beside $WT` when n > 0 (n counts renames that
     succeeded), else nothing.
   - The function always returns 0 and dies nowhere: a seeding failure never fails the pass, it only leaves the
     typecheck cold.
   Called from `typecheck_green` after the `typecheckCommand` read and before the run. With no command set, nothing
   is seeded.
   Catches: a fresh worktree's first closing-pass typecheck compiling cold when a sibling holds a usable cache (here
   0.91 s cold against 0.30 s seeded, L2; on #386's project a 152 s spike), which pushes a slow project toward the
   300 s limit and a no-result refusal.
2. `typecheck_green` (:1374-1376): the run is bounded and a timeout is its own result:
   ```
   local cap=${COMMANDECK_TYPECHECK_TIMEOUT_S:-300} rc=0 t0=$SECONDS
   (cd "$WT" && timeout -k 10 "$cap" bash -c "$cmd") >"$log" 2>&1 || rc=$?
   ```
   rc 0 is green, as now. rc 124, or rc 137 with `SECONDS - t0 >= cap`, dies with:
   ```
   no result from: typecheck. `<cmd>` ran past <cap>s in <WT> and was stopped (log <log>); no reviewer was run. Run the pass again: builder-codex-pass.sh <unit> <n> final
   ```
   Any other rc keeps today's red message. The function's comment (:1363-1366) adds the bound and the seeding.
   Catches: a typecheck that hangs (a watch-mode command, a lock never released; `sleep 30` stands in) and blocks the
   closing pass with no end, so the Builder sees a stalled pass and no line naming the check that gave no result.
3. `docs/review-loop.md:26-28`: the typecheck has a 300 s limit, and a run past it stops the pass naming the check
   that gave no result. A fresh worktree's typecheck cache is copied from a sibling worktree when the project's
   typecheck keeps one.

Produces: seeded ignored files in `$WT` (Data design) and the `no result from: typecheck` die. Consumes:
`typecheckCommand` (unchanged), `$WT`'s siblings, `git check-ignore`, coreutils `timeout` (already used at :1307,
:1405). Consumers of a changed contract: `typecheck_green`'s exit, which is `die` (exit 2) on red and on a timeout
alike, so its caller at :1390 is unchanged. Nothing reads the seeded files but the project's typecheck. The suite's
`tracked_state` (:1402) counts tracked files only, so an ignored seed does not trip it.

Acceptance tests (`scripts/__tests__/builder-codex-pass-rebase.test.sh`, after :71, each a closing pass as the
existing three are; the sibling is `"$(dirname "$W")/sib"`, and `.cache/` is ignored through the common git dir's
`info/exclude`):
- "a closing pass seeds the typecheck cache from a sibling worktree" (sibling `.cache/tc.tsbuildinfo` holds `SEED`,
  `$W` is a fresh worktree with no `.cache/` folder at all (the judge's input),
  `typecheckCommand = "grep -qx SEED .cache/tc.tsbuildinfo"`: green, one `typecheck cache: seeded 1` line)
- "a seed that cannot be copied leaves a cold typecheck and the pass runs" (the sibling's `.cache/tc.tsbuildinfo` is
  `chmod 000`, `typecheckCommand = "test ! -e .cache/tc.tsbuildinfo"`: green, no seeded line, no
  `.cache/tc.tsbuildinfo.*` temp file left in `$W`)
- "a present typecheck cache is never overwritten" (`$W/.cache/tc.tsbuildinfo` holds `OWN`; the command greps `OWN`:
  green, no seeded line, the file still `OWN`)
- "only an ignored typecheck cache is seeded" (the sibling's `build/x.tsbuildinfo`, not ignored in `$W`: absent in
  `$W` after the pass)
- "a typecheck past its time limit names the check that gave no result" (`COMMANDECK_TYPECHECK_TIMEOUT_S=1`,
  `typecheckCommand = "sleep 30"`: exit 2 within 20 s, one `no result from: typecheck` line on stderr, no reviewer
  round)
- existing :62, :65, :68 unchanged; :68 "a green typecheck lets the closing pass run" also counts 0 seeded lines (no
  sibling holds a cache)

Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a typecheck past its time limit names the check that gave no result -- scripts/builder-codex-pass.sh the timeout call and its 124/137 branch (replaced by the unbounded run)
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a closing pass seeds the typecheck cache from a sibling worktree -- scripts/builder-codex-pass.sh the seed_typecheck_cache call
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a closing pass seeds the typecheck cache from a sibling worktree -- scripts/builder-codex-pass.sh the mkdir -p of the seed's parent folder
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a seed that cannot be copied leaves a cold typecheck and the pass runs -- scripts/builder-codex-pass.sh the failure fallback of the seed copy (its `|| rm -f` branch replaced by `|| die`)
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a present typecheck cache is never overwritten -- scripts/builder-codex-pass.sh the exists skip in seed_typecheck_cache
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- only an ignored typecheck cache is seeded -- scripts/builder-codex-pass.sh the check-ignore skip in seed_typecheck_cache
Break: scripts/__tests__/typecheck-seed-build-mode.test.sh -- a seeded build-mode typecheck still reports the worktree's type error -- scripts/builder-codex-pass.sh the touch -t 198001010000 of the seed copy

### C6 -- #402 recorded, release (~13 lines, 2 files)

#402 needs no code (Decision 1). `CHANGELOG.md` gets one entry, and `.claude-plugin/plugin.json` the version, plus
any other file `bash ci/version-check.sh` names. README rows that describe the changed checks stay true as
written (`README.md:23-24` helpers and the Codex helper, `:115` the typecheck row; read 2026-10-27), so README is
unchanged.

Produces: the release entry and the version. Consumes: every other cut, done. Consumers of a changed contract: none.

## Data design

- Seeded cache files `$WT/<rel>.tsbuildinfo` (new writer, C5). Where they live: inside the Builder's worktree, at
  paths git ignores there. Writer: `seed_typecheck_cache` only, once per closing pass, only where the file is absent.
  The project's typecheck then rewrites it as it always did. The seeder may also create the file's ignored parent
  folders (`mkdir -p`); after a failed copy they stay, empty. Reader: the project's typecheck. Reset: the worktree's
  removal. Retry: a rerun finds the file present and seeds nothing. A torn copy cannot land: the copy goes to
  `<rel>.$$` and is renamed into place. A copy of a sibling's file caught mid-write by its own tsc is still safe: tsc
  reads an unreadable buildinfo as none and compiles cold (A5). The copy is dated 1980 before the rename, older than
  any source: `tsc -b` calls a project current when its buildinfo is newer than every input and then reads no source,
  so a fresh-dated copy passed the worktree's changed code unchecked (pass 1). Dated old, every input is newer, and tsc
  checks each source against the copy's recorded file hashes: unchanged files stay warm, changed ones are checked.
- Helper metrics rows `<main>/.claude/metrics/codex-helper.jsonl` (changed writer, C2). Where they live: main's
  checkout, one JSON line per `codex-ask.sh` call. Writer: `record` in `scripts/codex-ask.sh`, one `>>` append of one
  line (a torn last line gets a fresh one). C2 adds rows for two exits that wrote none before: the temp-folder failure
  and the inside-a-worktree refusal, each outcome `failed`, `model` null, `secs` 0, `bytes` 0, the existing shape.
  Readers: the build review (`codex_helpers_for` in `skills/worktreereview/scripts/collect.py`, rows of its unit; a
  line that is not JSON is skipped, a null model is read as none) and the operator (`docs/configuration.md`). Reset:
  `uninstall.sh` removes the file; nothing else does. Retry: a rerun is a new call and appends its own row, so a
  refused call and its retry are two rows, as every call is one.
- No other state is added or changed. C1, C3 and C4 change pure functions of their input, and #402 is unchanged.

## Guards changed (each blocks more than before; what it blocked before and after)

| guard | blocked before | blocks after |
|---|---|---|
| `plan-check.sh` placeholder lines | nothing (flagged, exit 0) | a placeholder line outside a fence that is not a `Placeholder:` line and cites no issue |
| `edit-content-tripwires.sh` / merge step 1 (#400) | placeholder copy on any added screen line, comments included | the same copy plus `under construction`, on code only: comment-only lines and a closed leading comment no longer count |
| `codex-ask.sh` | a judge or reviewer seat; a Claude-review setup | also a working folder inside the repository or any of its worktrees |
| `agent-model-guard.sh` | rewrote a pane's general-purpose naming haiku to sonnet | keeps it (blocks less, as the host does) |
| Codex judge and reviewer seats | nothing about sub-agents | start with sub-agents off |
| closing-pass typecheck | a red run | also a run past 300 s, named as no result |

Unchanged: Claude seats, non-reviewer Codex launches, the pass's broker reviewers (L5), a project with no
`typecheckCommand`, Explore enforcement, the approval syntax and counts.

## Prior art

Port-by-commit from the host's reference implementations: `853980ed`, `80c5b6a2`, host `paths.sh`, `fea64e3e`. No
outside library. Build-cache reuse across checkouts (TypeScript's incremental `.tsbuildinfo`, which records file
versions, so a stale seed costs only a recheck), and fail-closed timeouts with the check named (CI step timeouts,
`timeout(1)` exit 124). Least privilege for review agents (sub-agents off, rules files ignored, read-only sandbox).

## Decisions

1. **#402 is already built; this unit closes it without code.** 35c05ca built the host's hold. `helper_out`
   (`scripts/main-watch.sh:261-267`) holds while `PP_SESSION_BG > 0` within `HOLD_S` of the record's last write.
   0.52.0's notes announced it (`CHANGELOG.md:45`), but the merge message did not close the issue. The three cases the
   issue names are at `main-watch-helper-hold.test.sh:76-93`, and the test goes red when the hold is removed (A1).
   Test: main-watch-helper-hold.test.sh -- "bg job: a Builder waiting on its open background job was posted as stopped", "bg job: a Builder whose job stayed open past HOLD_S was not posted", "bg job: a Builder still stopped after its job's notification landed was not posted" (run by name, since this unit changes no file it covers; its PASS line goes in the evidence file)
2. **#402: the plugin's shape stays.** The host calls `pp_session_bg_open` and checks it before the event log. The
   plugin reads the same count through its incremental twin `pp_session_summary` (issue 299) and checks it after.
   Either check returns 0 on its own, so the order changes no result. The dashboard's builder state already reads
   the count (`scripts/dashboard.sh:379-381`, `scripts/dashboard_builders.jq:90-104`); the host commit does not
   touch its dashboard. Test: the same three checks; `dashboard-built.test.sh:108-132` (bg_open counts), unchanged.
3. **`under construction` is ported; the plugin's `later release` phrase stays (#400).** The host's list lacks the plugin's
   phrase, and dropping it would let that copy through. Test: "under construction copy in screen code is refused" (#400).
4. **Comment lines are not placeholder UI (#400).** This is the host's rule. A comment does not ship to a screen, and
   refusing one costs a Builder a round. A trailing comment and code after a closed leading comment are still
   screened, as on the host. Only a line whose code part is nothing but a comment is exempt: an inline JSX comment
   inside a real element (`<div>{/* ... */}</div>`) is still screened whole. Test: "a comment line in screen code is not placeholder copy", "copy after a closed JSX comment is refused", "placeholder copy and a disabled control in a comment-only line merge", "an inline JSX comment inside a real element is still refused".
5. **plan-check refuses, as the host does (#400).** The plugin's #398 chose to flag (that plan's Decision 16). The
   owner's #400 order is to bring the plugin in line with what the host shipped, and the host refuses. The host's
   exemptions come with the refusal (fenced lines, `Placeholder:` lines, a line citing an issue), so a plan can
   still quote an example or track a known item. Test: "a plan that describes placeholder UI as context is refused and launches nothing", "a fenced or issue-citing placeholder line passes", "plan-check alone exits 2 on a placeholder context line".
6. **The rest of #398 keeps the plugin's design.** It keeps the pipe-form `Placeholder:` approvals read from local
   main's plan and rulings, the `screenPaths` setting, the strict-tier edit hook, per-line approval counts, no pass
   line, and the single-line disabled pattern. Each was a judged decision of the 0.52.0 plan, and each stands on a
   plugin fact the host lacks. The plugin has no branch-name convention for a fork-point plan and no fixed screen
   folder. Bash 3.2 and BSD awk ended the parser rounds there with stated misses. The host's continuation form
   (`disabled` alone at a line's start) would refuse a wrapped JSX text line that starts with the word, which is why
   the host keeps it out of its own plan-check. Test: the existing `merge-unit-local-screens.test.sh` cases, unchanged, including "a disabled attribute on its own line inside a tag is a stated miss".
7. **A helper may run on the search model, named in any case or as a full id (#400).** The host keeps a pane's
   general-purpose call whose named model, lower-cased, contains sonnet or haiku. The plugin's adaptation: a call
   whose named model, lower-cased, contains its type's map model or the search model (`helpers.Explore`) keeps it.
   #400 asks the plugin to match the host, and an exact match would rewrite `claude-haiku-4-5` to Sonnet. A cheaper
   model than the configured one is never a cost leak. An absent map entry is skipped, so a partial map still enforces. Test: "a Builder's general-purpose call naming haiku keeps Haiku", "a Builder's general-purpose call naming claude-haiku-4-5 keeps it", "a Builder's Explore naming claude-sonnet-5-5 runs as Haiku", "a partial helper map still runs a general-purpose call naming opus as Sonnet".
8. **The rest of #397 keeps the plugin's design.** Models come from routing, debugger is enforced, and panes are
   detected by seat. The plugin's routing is its config surface, and its #397 enforced debugger by name. Test: the existing `agent-model-guard.test.sh` cases, unchanged.
9. **`--ignore-rules` is ported (#400).** It keeps user and project exec-policy rules out of a read-only call.
   Test: "the call runs read-only outside the repository" (its argv count).
10. **The working folder is fixed under `/tmp` and refused inside any worktree (#400).** Today an inherited TMPDIR
    inside the repository would make Codex load that tree's config, which breaks the "outside the repository" promise
    of the comment at `scripts/codex-ask.sh:40`. The refusal is a `failed` metrics row like any other failure, so
    `record` and `fail` are defined before the working folder is made. Test: "an inherited TMPDIR inside the repository is ignored", "a working folder inside a worktree is refused".
11. **The rest of #399 keeps the plugin's design.** It keeps the `--timeout` option with TERM then KILL, the
    6000-byte cut, the answering model read from Codex's header, the helper-pane gate and the metrics row. Each is
    stricter than or equal to the host's. The host's helper passes no `multi_agent` word either. Test: the existing `codex-ask.test.sh` cases, unchanged.
12. **`--disable multi_agent` rides the launch words for `agent: codex` with `reviewer: true` (#400 item 4).** This is
    the host's line. Claude reviewer seats already deny `Agent` through `tools`. Test: "plan-judge-sol on codex launches with multi_agent off", "plan-judge-sol on claude has no multi_agent word", "a Codex seat that is not a reviewer keeps multi_agent".
13. **#386 lands on the closing-pass typecheck only.** Every other check that runs at Stop or before a closing pass
    either runs no project command or already names its timeout (§1, the #386 table). No Stop hook is invented
    (L1). Test: "a typecheck past its time limit names the check that gave no result"; the named timeouts elsewhere are existing tests (`post-fix-checks.test.sh` "a hung check is cut off at the cap and named").
14. **The limit is 300 s, and a timeout refuses the pass.** That is about twice the issue's 152 s spike. A refusal
    matches a red typecheck (no reviewer on an unknown tree), and the message says "no result from:" in the host's
    words. Exit 137 counts as a timeout only past the deadline, so a typecheck killed by something else stays red.
    `COMMANDECK_TYPECHECK_TIMEOUT_S` exists for the test, as `POST_FIX_CHECK_TIMEOUT_S` does for post-fix. Test: "a typecheck past its time limit names the check that gave no result".
15. **Seeding copies from sibling worktrees only: ignored, absent files, renamed into place.** This is the host's
    rule ("only siblings: buildinfo paths are relative to the file"), measured here (L2, A3, A4). The main checkout
    sits at another depth and gave no gain. Never a tracked or present file. The parent folder is made first, and a
    failed seed is a cold compile, never a failed pass. Test: "a closing pass seeds the typecheck cache from a sibling worktree", "a present typecheck cache is never overwritten", "only an ignored typecheck cache is seeded", "a seed that cannot be copied leaves a cold typecheck and the pass runs".
16. **No CHANGELOG line for #402.** It shipped in 0.52.0 and that entry says so (`CHANGELOG.md:45`). Test: none, release-note text only.

## Accepted failure modes

1. A typecheck that writes no buildinfo (setup's default `npx tsc --noEmit`) gains nothing from seeding and runs
   cold each closing pass (L2). Test: "a green typecheck lets the closing pass run" (no seeded line when no sibling has a cache).
2. A seed from a sibling built by another tsc version or another config is rebuilt cold by tsc. Test: none, tsc's own buildinfo check; A5 measured a corrupt seed compiling cold with every error reported.
3. The seeding scan's cost grows with the sibling trees (L4). Test: none, a cost bound measured in L4.
4. A JSX text line that starts with `*` reads as a comment and is not screened, as on the host. Test: none, the review's placeholder P1 lens (`scripts/builder-codex-pass.sh:141-142`) still reads every line.
5. The pass's broker reviewers do not get the `multi_agent` word (L5). Test: none, the host's passes are the same; the read-only sandbox and the prompt's diff bound them.

## Assumptions (each settled, or a Builder check with the action per outcome)

- A1 [settled] #402's test guards the fix. On a scratch copy of HEAD (`git archive HEAD`), on the Mac, 2026-10-27:
  - `bash scripts/__tests__/main-watch-helper-hold.test.sh` printed `PASS main-watch-helper-hold.test.sh` in 27.3 s.
  - With `helper_out`'s two session-record lines replaced by `return 1`, it exited 1 with `FAIL: bg job: a Builder
    waiting on its open background job was posted as stopped`.
- A2 [settled] No host commit after the cited ones touches their files (`git log` per file, 2026-10-27).
- A3 [settled] A sibling-seeded buildinfo reports what a cold run reports. On the Mac, 2026-10-27, tsc 6.0.3, two
  copies of HEAD side by side:
  - The diagnostics of the cold run and of the seeded run sort to the same md5 (`215d0a5b...`).
  - With `export const x: number = "planted";` appended to `hooks/units-sources.ts` and the seed copied in, the
    seeded run reported the TS2322 for that file (1 line), as the cold run did (1 line).
- A4 [settled] A seed from another folder depth gives no gain: 0.86 s against 0.91 s cold (L2). The buildinfo's
  first entry is a relative path climbing to the global TypeScript lib
  (`"../../../../../../../../../../../opt/homebrew/lib/node_modules/ty...`), which resolves the same only at the same
  depth.
- A5 [settled] A corrupt seed is safe. With `.cache/tc.tsbuildinfo` holding `{"program": {garbage`, tsc exited 2 with
  the full diagnostics and rewrote the file (2026-10-27).
- A6 [settled] The resolved seat carries `.agent` and `.reviewer` when the words are built. `pp_route_json
  plan-judge-sol` printed `{"agent":"codex",...,"reviewer":true,...}`, and the env word already tests `.agent ==
  "claude"` (`scripts/paths.sh:874`).
- A7 [Builder check, before C1] Route a Codex seat that is not a reviewer in `seat-launch.test.sh`: a
  `COMMANDECK_ROUTING` overlay giving `builder` `agent: codex` and a Codex model, then `pp_route builder` and `RT_CMD`.
  If `check_seat` accepts it, the case asserts `multi_agent` is absent from `RT_CMD`. If it refuses a Codex builder,
  the case uses a copy of `plan-judge-sol` with `reviewer: false` instead. Either way the case exists, and the
  evidence file says which.
- A8 [settled] `codex exec --help` on codex-cli 0.164.0 lists `--ignore-rules` ("Do not load user or project
  execpolicy `.rules` files") and `--disable <FEATURE>` (2026-10-27).
- A9 [settled] (#400) The tripwire test's comment line, `// Export lands under construction`, is not caught by the
  vague-comment rule at `hooks/edit-content-tripwires.sh:275` (`implement later|temporary fix|placeholder|will be
  replaced|needs refactor|come back to this`), so the case tests the screen rule alone (#400).
- A10 [Builder check, before C4 item 5] B1 above. Expected: only the three listed flips. Any other match gets a fence
  or cite (not a placeholder case) or is listed as a flip in the evidence file (a placeholder case).

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| a typecheck that never ends | `typecheckCommand = "sleep 30"`, `COMMANDECK_TYPECHECK_TIMEOUT_S=1`, a closing pass | exit 2 within 20 s, `no result from: typecheck`, no reviewer round | a typecheck past its time limit names the check that gave no result |
| a fresh worktree with no cache folder | `$W` has no `.cache/`, a sibling's `.cache/tc.tsbuildinfo` = `SEED`, `typecheckCommand = "grep -qx SEED .cache/tc.tsbuildinfo"` | the folder is made, the seed lands, green, one seeded line | a closing pass seeds the typecheck cache from a sibling worktree |
| a sibling's cache file git tracks or does not ignore | the sibling holds `build/x.tsbuildinfo`, `build/` not ignored in `$W` | not copied | only an ignored typecheck cache is seeded |
| TMPDIR points inside the repository | `TMPDIR=$W/tmpx`, a Builder pane's `codex-ask.sh 'q'` | Codex runs in a folder under `/tmp`, rc 0 | an inherited TMPDIR inside the repository is ignored |
| a placeholder line in a fence, or citing an issue | a plan line naming placeholder copy (#400) inside a fence, then outside one with `(#12)` | plan-check exit 0 both times | a fenced or issue-citing placeholder line passes |

Moved out of the table by its five-row cap, tests unchanged among the acceptance tests:
- the worktree already has its cache (C5, "a present typecheck cache is never overwritten")
- a seed that cannot be copied (C5)
- a mktemp that lands inside a worktree, and its metrics row (C2)
- a comment-only line, a closed leading comment, and an inline comment inside a real element (C4)
- plan-check run alone on a placeholder line (C4)
- a general-purpose helper naming haiku or a full model id (C3)
- a partial helper map with no Explore entry (C3, "a partial helper map still runs a general-purpose call naming opus as Sonnet")
- a Claude judge with no `multi_agent` word (C1)

Added by pass 1 (beyond the table's cap; each with its test):
- a seeded buildinfo newer than the worktree's changed sources, `typecheckCommand = "tsc -b"` (C5, pass 1
  cache-false-green and stale-typecheck): the seeded run reports the worktree's TS2322 as a cold run does, and a
  worktree that matches the sibling stays green, with the real compiler.
  Test: scripts/__tests__/typecheck-seed-build-mode.test.sh -- "a seeded build-mode typecheck still reports the
  worktree's type error", "a seeded build-mode typecheck of a worktree that matches the sibling is green"
- a plan or batch that quotes placeholder UI in a tilde fence, an indented fence, or a longer fence holding a shorter
  delimiter (C4, pass 1 fence-parser): plan-check passes it, and a size line quoted in such a fence is not the plan's.
  Test: scripts/__tests__/plan-check-placeholder-fences.test.sh (all five checks)

## Claims to falsify

- The plugin registers no Stop or SubagentStop hook that runs a project command.
- `main-watch-helper-hold.test.sh` goes red when `helper_out`'s session-record hold is removed.
- A seed from a sibling at the same depth gives the same diagnostics as a cold run, planted errors included.
- A seed from a checkout at another depth gives no speedup.
- A corrupt seeded buildinfo makes tsc compile cold and report every error.
- No closing pass starts a reviewer after a typecheck timeout.
- A typecheck that exits 137 before its deadline is reported red, not as no result.
- The seeder never writes a tracked or unignored file and never overwrites a present one.
- A fresh worktree with no cache folder is seeded.
- A seeding failure never fails the closing pass.
- A project with no `typecheckCommand` seeds nothing and runs no typecheck.
- Every seat but a Codex reviewer or judge launches with the same command as before.
- `codex-ask.sh` never runs Codex in a folder inside the repository or any of its worktrees, whatever TMPDIR is.
- Every `codex-ask.sh` call past the pane and route gates, the worktree refusal included, writes one metrics row.
- In a helper pane, a general-purpose call naming sonnet or haiku, in any case or as a full model id, runs as named,
  and one naming anything else runs as sonnet.
- In a helper pane, Explore always runs as haiku.
- With a helper map that has no Explore entry, a general-purpose call naming opus runs as sonnet.
- A comment-only screen line is never refused for placeholder copy, and a line with code after a closed leading
  comment is screened.
- An inline JSX comment inside a real element is screened as the whole line.
- `plan-check.sh` exits 2 on a refused placeholder line, whichever caller runs it.
- The merge's per-line disabled count equals the old whole-file count on every non-comment added line.
- Every plan and batch the launch-line tests passed before, but the three flipped checks, still passes plan-check.

## Not ordered (found, not planned)

- `pp_session_bg_open` (`scripts/paths.sh:150-170`) has no production caller. It is the full-read oracle that
  `dashboard-built.test.sh` and `dashboard-collector-incremental.test.mjs` check `pp_session_summary` against, so it
  stays.
- Seeding the full suite's caches: the host seeds only its typecheck.

## Progress notes

- #402: built
- #400: built
- #386: built

## Version and CHANGELOG

Version: the next free minor at merge time (0.53.0 if nothing lands first; `bash ci/version-check.sh` decides), in
`.claude-plugin/plugin.json`. One entry, in the release-note style (topic sections named for what a user sees, plain
sentences, no file names, paths, issue numbers or hashes). Draft:

```
## 0.53.0 -- <merge date>

### Planning

- A plan or batch that describes placeholder UI is refused at launch, unless the line approves it, sits in a quoted block, or names the issue that tracks it.

### Builders

- Helper agents may run on the search model when a call names it; any other model still runs as the configured one.
- The read-only Codex helper always works from a temporary folder outside the project, refuses to run inside any of its worktrees, and loads no rules files.

### Reviews

- Codex plan judges and reviewers start with sub-agents switched off.
- The typecheck before a closing pass has a five-minute limit. A run past it stops the pass and says the typecheck gave no result.
- A new build's first typecheck reuses the typecheck cache of a neighbouring build, so it runs about as fast as later ones.

### Merging

- Comments in screen code no longer count as placeholder UI, and "under construction" now does.
```

## Merge commit message

```
feat(plugin-open-2026-10-27): reconcile with the host twins, Codex seats without sub-agents, a bounded and warm closing-pass typecheck

Closes #402
Closes #400
Closes #386
```

A cut left partial changes its `Closes #N` to `Refs #N` and its progress note to `#N: partial -- <what is left>`.

## Done when

- Every acceptance test named above is green. `main-watch-helper-hold.test.sh` is run by name, and its PASS line goes
  in the evidence file.
- `bash scripts/run-shell-tests.sh --changed main` is green.
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- Each `Break:` line has its `Mutation-verified:` row.
- A closing (final) pass ends `VERDICT: GO` with no finding named.

## Plan change log

- 2026-10-27: first version.
- 2026-10-27, F1: C5 item 1 makes the seed's parent folder (`mkdir -p`) before the temp-file copy; any seeding failure is a cold compile, never a failed pass. The seeding test's `$W` has no `.cache/`; new test "a seed that cannot be copied leaves a cold typecheck and the pass runs"; two Break lines; Data design, Decision 15, What can go wrong row 2, claims.
- 2026-10-27, F2: C4's merge test now uses comment-only fixtures ("... in a comment-only line merge"), and the `<div>{/* ... */}</div>` line is the refused test "an inline JSX comment inside a real element is still refused"; Decision 4, a Break line, a claim.
- 2026-10-27, F3: C4 item 5 runs the refusal loop in the calling shell (numbers gathered into a variable, no `| while`), so `refuse` exits the script 2; new test "plan-check alone exits 2 on a placeholder context line" and its Break line; Decision 5, a claim.
- 2026-10-27, F4: C2 item 0 moves `record` and `fail` above the working folder with starting values for their inputs; the refusal calls `fail failed`, and the mktemp failure now writes its row too. "a working folder inside a worktree is refused" asserts the metrics row; a Break line, Decision 10, a claim.
- 2026-10-27, F5: C3 ports the host's case-insensitive family match (`contains` on lower-cased names, read from the routing map). New tests "a Builder's general-purpose call naming claude-haiku-4-5 keeps it" and "a Builder's Explore naming claude-sonnet-5-5 runs as Haiku"; a #400 table row, Decision 7, a Break line, a claim.
- 2026-10-27, F6: `Catches:` lines on C4's B1 check, C5's cache discovery (item 1) and C5's timeout gate (item 2).
- 2026-10-27: size line 240 -> 288 changed lines (C2 ~42, C3 ~16, C4 ~125, C5 ~80); the four new plan lines that quote placeholder copy cite #400 so the revised plan-check passes this plan.
- 2026-10-27, F7: C3's family match drops absent map entries (`$h.Explore // empty`) before `ascii_downcase`, so a partial map still enforces. New test "a partial helper map still runs a general-purpose call naming opus as Sonnet" and its Break line; Main answers, Decision 7, a moved-out What can go wrong case, a claim; size 288 -> 292 (C3 ~16 -> ~20).
- 2026-10-27, build: "plan-check alone exits 2 on a placeholder context line" runs u31's line in a plan that passes every other plan-check (a What can go wrong section added), so only the placeholder refusal can exit 2; its break run (loop behind a pipe) was green on u31's bare plan, which plan-check refuses for the missing section anyway.
- 2026-10-27, fix r1: C5's seed copy is dated 1980 before its rename (a fresh-dated copy let `tsc -b` skip changed
  sources); new test file typecheck-seed-build-mode.test.sh and its Break line. Data design names the helper metrics
  file C2 writes new rows to, and C2's reader sentence names the build review. Plan-check and the Break-line gate use the
  one fence rule (`PP_AWK_FENCE`, moved from paths.sh to scripts/fence.sh), and the Post-merge reader drops tilde and
  indented fence lines as it drops backtick ones; new test file plan-check-placeholder-fences.test.sh. Two What can go wrong cases.

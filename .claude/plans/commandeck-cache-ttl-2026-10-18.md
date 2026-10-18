# Plan: commandeck-cache-ttl-2026-10-18 -- setup/update default the main-conversation prompt-cache lifetime per role

Order: owner, 2026-10-18 (owner ruling). Main and worker panes 5m, relay pane 1h. Setup
and update ask each one with a "Leave as is" option and the cost stated plainly. Nothing is written without the
answer. A rewrite of the relay's `.claude/settings.local.json` keeps its other `env` entries.

## Facts this plan rests on (checked)

- Claude Code 2.1.302 picks the main-conversation TTL in this order: `FORCE_PROMPT_CACHING_5M`, then the
  `CLAUDE_CODE_PROMPT_CACHE_TTL` env var, then the `promptCacheTtl` setting, then the default. The default is 1 hour
  on a Claude subscription within its usage limits and 5 minutes on an API key, Bedrock, Vertex or Foundry.
  (From the binary's settings schema text and its TTL resolver.) So an env entry beats the setting, and
  "unset" is not 5m for a subscription owner.
- Which files a pane in a git worktree reads, lowest to highest. Settings merge key by key, so `env` merges per
  variable:
  1. user `~/.claude/settings.json`;
  2. project: the worktree's own `.claude/settings.json` (its checked-out copy);
  3. local, two files: first the worktree's own `.claude/settings.local.json`, then the main checkout's
     `.claude/settings.local.json` over it. Where both set the same key, the main checkout's value applies;
  4. flag (`--settings`) and managed policy over all.

  Sources:
  - The docs: <https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository>
    (read 2026-10-18). "In a worktree, it uses the file at the main checkout's root." The starting directory's
    file, the one versions before 2.1.211 used, is still read "alongside the root file; where both set the same
    key, the root's value applies". The root rule has exceptions: no git repository, a root that is `$HOME`,
    Windows, or a root or `.git`/`.claude` entry not owned by the user. Then the starting directory's file alone
    is the local file.
  - The 2.1.302 binary's loader agrees. `localSettings` resolves to `canonicalGitRoot`. The worktree's own file
    is the "legacy" path (`cwd/.claude/settings.local.json` when cwd differs from the root), merged as
    `merge(legacy, root)`, so the root wins.
  - Telemetry `tengu_dead_probe_legacy_local_settings` counts reads of that legacy file. That points to a
    possible future removal (see Risks).
- So, in the owner's live config, the relay's 1h holds only because the main checkout's local file has no
  TTL key: user `env.CLAUDE_CODE_PROMPT_CACHE_TTL = "5m"` (tier 1) loses to relay worktree
  `env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h"` (tier 3, worktree file). A TTL in the main checkout's local file
  would beat the relay's, and every worker's too.
- Every reader and writer today (rg over scripts, skills, templates, hooks, ci, README.md, CHANGELOG.md):
  - `scripts/install-lib.sh:183-201` `il_cache_ttl`: writes `promptCacheTtl: "1h"` and
    `subagentPromptCacheTtl: "5m"` into the project's `.claude/settings.json` and skips keys already there.
    Called by `scripts/setup.sh:391` (`off` unless `CACHE=recommended`) and `scripts/uninstall.sh:39` (`off`).
  - `scripts/setup.sh:37-40` (header), `:111` (reads `.cacheTtl`), `:206` (`--cache-ttl recommended|default`),
    `:53` (`TAKES` list), `:360/375` (saves `cacheTtl`).
  - `scripts/worktree-setup.sh:143-146,154,170`: Builder only, `.env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h"`
    (owner 2026-10-11). The relay branch (`:52-74`) writes no `env` and replaces no `env`.
  - `scripts/builder-cache-check.sh:2-4,26`: fails unless a Builder's main thread wrote only 1h cache.
    Its test: `scripts/__tests__/transcript-requests.test.sh:116-120`. `scripts/proof-run.sh:123` names it only.
  - `skills/setup/SKILL.md:162-164`: the "Prompt cache" question (1h main, 19% figure).
    Pinned word for word by `scripts/__tests__/plugin.test.sh:135-136`.
  - `README.md:157` (setup table), `README.md:432-434` (the cache check says 1 hour).
  - `CHANGELOG.md:269-273`: history of 0.x; left as it is.
  - No hook, template or startup text names the cache: `scripts/startup-size.sh` numbers do not move.
  - `il_cache_ttl` has no test today.
- The project's `.claude/settings.json` reaches a worktree only after it is committed (`scripts/setup.sh:582`
  says so). A worktree's own `.claude/settings.local.json` is the one file read by that pane alone, and it loses
  only to the main checkout's local file (above). Today's Builder 1h also lives there, and as an env entry it
  would beat a 5m setting anyway.

## Numbers for the cost lines

The three scripts, rerun at plan time (48-hour window ending 2026-10-18 about 06:00; list prices; read-only):

| Pane | gaps 5-60 min | 5m vs 1h |
|---|---|---|
| main | 1.1% | 5m about 5% cheaper |
| Builder / fixer / planner | 0.6% / 0.2% / 0.7% | 5m 6% / 17% / 14% cheaper |
| relay | 5.0% | 5m about 85% dearer |
| subagents (1h simulated) | 0.2% | 1h about 34% dearer |

Why: 1h writes cost 2x input against 1.25x for 5m. They pay back only when the pane pauses 5 to 60 minutes
between requests. Main and workers almost never do. The relay waits on the owner. The old 0.x text ("a 5-minute
cache cost main about 19% more") is wrong on today's data and goes.

The scripts measured each role's 5m cost against its 1h cost. The questions quote them that way, with no
reversed percentages:
- main and workers: "a 5-minute cache cost about 5% less for main and 6 to 17% less for worker panes";
- relay: "a 5-minute cache cost about 85% more", as measured. Read the other way, 1h costs about 46% less than
  5m (1 - 1/1.85), but the question quotes the measured direction.

Numbers are rounded. Nothing personal from the scripts ships.

## Design (the answers and where each is written)

Two answers, two flags, both stored in `.claude/commandeck.json`:

| Answer | Flag | Stored | Written on `5m` / `1h` | On `leave` |
|---|---|---|---|---|
| main and workers | `--cache-ttl 5m\|leave` | `.cacheTtl` | main: `promptCacheTtl: "5m"`, `subagentPromptCacheTtl: "5m"` in the project's `.claude/settings.json` (`il_cache_ttl`, same home and manifest as today); every non-relay worktree: `env.CLAUDE_CODE_PROMPT_CACHE_TTL = "5m"` in its `.claude/settings.local.json` (`worktree-setup.sh`) | nothing |
| relay | `--relay-cache-ttl 1h\|leave` | `.chiefOfStaff.cacheTtl` | relay worktree: `.env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h"` (a jq path assignment: every other `env` key stays) | nothing |

- An old stored value (`recommended`, `default`) or none counts as "not answered". Setup then writes nothing for
  the cache: it neither adds nor takes out. Setup prints one `Needs you` line per unanswered question.
  `update.sh` already shows that block (`scripts/update.sh:64`), and the update skill asks on it.
- `--cache-ttl recommended|default` dies with "takes 5m or leave", the same way a bad value dies today.
- `il_cache_ttl` replaces a key only when it is absent, or when it still holds the value setup recorded in the
  manifest (setup's own, unchanged since). A value the owner set stays, as today. `off` (uninstall) is unchanged.
- Workers get the env entry, not only the project setting. Two reasons: the project file reaches a worktree only
  by commit, and a leftover Builder `env` 1h would beat a 5m setting.

### The relay's answer is the effective value: every TTL write, and why none beats the relay's

| Write | File, tier | Reaches the relay pane? |
|---|---|---|
| `promptCacheTtl` / `subagentPromptCacheTtl` 5m (`il_cache_ttl`) | main checkout `.claude/settings.json`, project tier, and a setting, not env | It reaches the relay worktree only by commit. Even then any env TTL beats a setting, and the relay's is env. |
| worker `env` 5m (`worktree-setup.sh`) | each worker worktree's own `.claude/settings.local.json` | No: another worktree's file. |
| relay `env` 1h (`worktree-setup.sh`) | the relay worktree's own `.claude/settings.local.json`, local tier (worktree file) | It is the relay's value. |
| nothing | main checkout `.claude/settings.local.json` | Setup puts only permission rules there (`il_allow_set`). No plugin code writes an `env` key there, before or after this change. |

So the relay's 1h is the highest TTL any plugin write produces for that pane. It beats the owner's user-tier
env, here 5m. Four things outside the plugin can still beat it:
- a TTL in the main checkout's local file;
- `FORCE_PROMPT_CACHING_5M` in any file;
- a flag or managed-policy file;
- the shell env, if settings env does not override it.

The design keeps the first one out by a check, not an edit. The value is the owner's, and setup never deletes
an owner's key. The check also computes the relay's effective TTL from the files, in the order above. FORCE is
named as a fact only: an owner who sets it wants 5m everywhere.

The invariant, and setup and the doctor check it (item 3b): when either answer is set (5m or 1h), the main
checkout's `.claude/settings.local.json` carries no `env.CLAUDE_CODE_PROMPT_CACHE_TTL`. If it does, setup lists
it under Needs you and the doctor warns. The warning names the file and the value every worktree pane then runs
on, and says to move the key to `~/.claude/settings.json`, where the per-worktree values beat it.

Rejected: move the relay value to a tier above local (`claude --settings <file>` in the relay pane's launch
command). It is lost when the owner restarts the pane with plain `claude`, and it is new launch wiring in two
places (`setup.sh` `S_PANE`, `open_pane`). Not needed while the invariant holds.

## Items

Ponytail rung per item: 1 need, 2 in the codebase, 5 one line, 6 minimum code.

### 1. `scripts/install-lib.sh:183-201` `il_cache_ttl`: 5m, and replace setup's own earlier value (~8 lines)
- Rung 2: the existing function, home file and manifest record. Change the literal `"1h"` to `"5m"`. The
  `with_entries(select(...))` keeps a key when it is absent or when `$d[$k] == $r[$k]`. `$r` is
  `.entries[$f].cacheTtl // {}` from the manifest, the same read as the `off` branch. Update the comment:
  5m main, the 2026-10-18 numbers, and "setup's own earlier value is replaced".
- Rejected lazier: keep "skip any present key". Then an owner who chose the old recommended answer never gets 5m
  on main. Rejected: a new function. It would duplicate the manifest bookkeeping.
- Red first, in `scripts/__tests__/install-lib.test.sh` (extend; it already has the `lib` runner). Three
  checks, each failing today:
  (a) a settings file holding `promptCacheTtl: "1h"` that the manifest records as setup's: after the call it is
  `"5m"`, and the record says `"5m"`;
  (b) the same file with no record (the owner's own 1h): it stays `"1h"`;
  (c) then `il_cache_ttl ... off` takes out only setup's keys.
  Why: an update must move setup's own 1h and never an owner's (+~10 test lines).

### 2. `scripts/setup.sh`: the two answers, no write without one (~14 lines)
- `:206`: `--cache-ttl) case $2 in 5m|leave)`, and the die text says `5m or leave`. New `--relay-cache-ttl`
  line, same shape (`1h|leave`). `:53` `TAKES` gets `--relay-cache-ttl`. `:111` reads
  `RCACHE=$(old .chiefOfStaff.cacheTtl)`. `:357-376`: the `chiefOfStaff` object gets
  `cacheTtl: $rcache` inside the existing empty-value filter.
- `:391`: `[ "$CACHE" != 5m ] || il_cache_ttl "$IL_PROJECT" "$PSET"` (rung 5). Today's `off` call on any other
  answer goes, because it took out an earlier 1h on "default", and "leave" must keep it.
- After `NEED=()` (`:446`): one `case` line per answer. When `.cacheTtl` is not `5m|leave` it adds
  `Prompt cache: not answered since 0.15.0; /commandeck:setup asks, or: setup.sh --cache-ttl 5m|leave`.
  With a relay name and `.chiefOfStaff.cacheTtl` not `1h|leave` it adds the relay twin.
- The relay rewrite needs no new call. Setup already reruns `worktree-setup.sh` on an existing relay (`:507`).
- Header `:37-40`: the two flags in one sentence each.
- Rejected lazier: one flag for both roles. The order offers each default with its own "leave as is". Rejected:
  a whole `setup.sh` run as the test (owner ruling 2026-10-16, no install end-to-end). The flag `case` lines are
  trivial. The write is item 1's test, and the question text is item 5's.

### 3. `scripts/worktree-setup.sh`: workers 5m, relay 1h, `env` kept (~10 lines)
- Move the `PROJECT=` line (`:82`) above the relay branch (`:56`), so both branches read the same
  `commandeck.json`.
- Relay branch jq `:66-70`: `--arg rttl "$(jq -r '.chiefOfStaff.cacheTtl // empty' "$PROJECT/.claude/commandeck.json" 2>/dev/null)"`.
  Then `| if $rttl == "1h" then .env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h" else . end`. This is a path
  assignment, so every other `env` key stays. Never `.env = {...}`.
- Worker section: in the worker jq at `:123`, the same pattern on `.cacheTtl == "5m"` writes `"5m"`. Delete the
  Builder's `| .env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h"` (`:154`). Rewrite comment `:143-146`: Builders follow
  the setup answer like every worker (owner 2026-10-18, replacing 2026-10-11). Echo `:170` drops ", 1h prompt
  cache".
- `--print-settings` reads the same config, so `plan-worktree-close.sh` compares like with like.
- Rejected lazier: rely on the project `settings.json` for workers. It reaches a worktree only by commit, and a
  leftover Builder `env` 1h beats it.
- Red first, in `scripts/__tests__/worktree-setup.test.sh` (extend; +~10 lines). Seed the relay's file with
  `env: {"OTHER": "x"}`. Write `cacheTtl: "5m"` and `chiefOfStaff.cacheTtl: "1h"` into the fixture config.
  Checks:
  (a) relay `env == {"OTHER": "x", "CLAUDE_CODE_PROMPT_CACHE_TTL": "1h"}`. Why: the relay's other entries must
  survive.
  (b) `plain` and `bld` env TTL `"5m"`. `bld` is `"1h"` today, so red. Why: Builders are 5m now.
  (c) one more worktree run under `cacheTtl: "leave"` has no TTL key. Why: nothing without the answer.
- These checks inspect file contents only. Item 3b checks the effective value.

### 3b. `scripts/install-lib.sh` `il_cache_ttl_report`, `scripts/doctor.sh`, `scripts/setup.sh`: the relay's effective TTL (~18 lines)
- Rung 2: the house shape for a settings check is `il_auto_mode_report` (`install-lib.sh:238-252`, doctor
  `:112`, tested in `doctor.test.sh:82-94` by its `lib` runner). Add `il_cache_ttl_report` next to it. It prints
  `ok ...` or `warn ...` lines:
  - Nothing to check when neither answer is set (`.cacheTtl != "5m"` and `.chiefOfStaff.cacheTtl != "1h"`). It
    prints `ok prompt cache: setup sets none`.
  - When `$PP_MAIN/.claude/settings.local.json` has `env.CLAUDE_CODE_PROMPT_CACHE_TTL = <v>`, it prints:
    `warn prompt cache: <file> sets CLAUDE_CODE_PROMPT_CACHE_TTL=<v>, and Claude Code applies that file over every worktree's own settings, so the relay and worker panes run <v>; move the key to ~/.claude/settings.json`.
  - With the relay answer `1h` and the relay worktree present (`$PP_WORKSPACES/Chief-of-Staff`), it computes the
    relay's effective env TTL. The order is Facts' order: user file, the relay's `.claude/settings.json`, the
    relay's `.claude/settings.local.json`, the main checkout's `.claude/settings.local.json`. The jq is
    `jq -rs 'map(.env.CLAUDE_CODE_PROMPT_CACHE_TTL // empty) | last // "unset"'`, last one wins. Anything but
    `1h` prints `warn prompt cache: the relay pane runs <v>, not the 1h you chose` (rung 5).
  - Otherwise it prints one `ok` line.
- `scripts/doctor.sh`: one line after `:112`, the same `while read` dispatch. `scripts/setup.sh`: after the cache
  writes, `il_cache_ttl_report | grep '^warn'` lines go into `NEED`. Setup checks and never edits the owner's
  key. `update.sh` shows both (Needs you, then the doctor).
- Rejected lazier: a doc line only. The judge's case (main local 5m) would pass silently. Rejected: setup
  deleting the key. It is the owner's value, and the plugin never removes an owner's key.
- Why not a true effective-value test: the only full resolver is Claude Code itself. Starting it to read a
  resolved `env` needs a session (an API call), which a unit test must not make, and 2.1.302 has no command that
  prints merged settings. So the test pins the invariant and the file-order resolution that guarantee it.
- Red first, in `scripts/__tests__/doctor.test.sh` (extend, after the auto-mode block; +~10 lines). The function
  does not exist yet, so every check fails. Realistic config:
  - `$HOME/.claude/settings.json` holds `env.CLAUDE_CODE_PROMPT_CACHE_TTL = "5m"`;
  - the project's `commandeck.json` holds `cacheTtl: "5m"` and `chiefOfStaff: {name, cacheTtl: "1h"}`;
  - `COMMANDECK_WORKSPACES=$T/ws` with `ws/Chief-of-Staff/.claude/settings.local.json` holding `env` 1h;
  - the main checkout's `.claude/settings.local.json` is present, with permissions only.

  Checks:
  (a) one `ok prompt cache` line and no `warn`;
  (b) after adding `env.CLAUDE_CODE_PROMPT_CACHE_TTL = "5m"` to the main checkout's local file, two warns: one
  names that file, and one says `the relay pane runs 5m, not the 1h you chose`;
  (c) the relay's local file without the key (main local clean again) gives `the relay pane runs 5m`, from the
  user env.
  Why: the owner's 1h relay order is about the cost the pane really pays, not the bytes in one file.

### 4. `scripts/builder-cache-check.sh`: prove 5m, not 1h (~6 lines)
- Header `:2-4`: the main thread and subagents on 5 minutes (owner 2026-10-18; set by setup's prompt-cache
  answer). `:26`: `{ [ "$MM" -gt 0 ] && [ "$MH" -eq 0 ]; } || ... "the main thread must write only 5m cache"`.
- Rejected lazier: delete the check. `proof-run.sh:123`, README and a test name it. Deleting is no smaller, and
  it drops the owner's proof tool.
- Red first: flip the fixture at `scripts/__tests__/transcript-requests.test.sh:117` to
  `ephemeral_5m_input_tokens`. The expected line becomes `main thread 1h=0 5m=10`. Add one check that a 1h main
  thread now fails (exit 1). Why: the order replaced the 2026-10-11 1h, and the check must refuse the old state
  (+~3 lines).

### 5. `skills/setup/SKILL.md:162-164` and `skills/update/SKILL.md`: the questions (~12 lines)
- Setup, replacing `:162-164`:
  ```
  Ask "Prompt cache": 5m for main and workers (recommended) | Leave as is
  - 5m for main and workers: Main, Builders, reviewers and every other worker pane keep their cache 5 minutes, subagents too. On real sessions a 5-minute cache cost about 5% less for main and 6 to 17% less for worker panes: they seldom pause long enough for a 1-hour cache to pay. Saved in `.claude/settings.json` and each worktree's `.claude/settings.local.json`. `--cache-ttl 5m`
  - Leave as is: writes nothing; what is set now stays, a 1-hour value an earlier setup wrote included (on a Claude subscription an unset cache is 1 hour). `--cache-ttl leave`
  With a relay:
  Ask "Relay prompt cache": 1h (recommended) | Leave as is
  - 1h: The relay pane keeps its cache 1 hour. It waits on you between turns, and on real sessions a 5-minute cache cost it about 85% more than 1 hour. Saved in its worktree's `.claude/settings.local.json`; its other settings stay. The doctor warns if another file overrides it. `--relay-cache-ttl 1h`
  - Leave as is: writes nothing in the relay's settings. `--relay-cache-ttl leave`
  ```
- Update: after the relay paragraph, add one paragraph. If update shows a `Prompt cache:` or
  `Relay prompt cache:` line under Needs you, ask that question from `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`
  word for word. Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh` with only that flag. Never run it without
  the answer.
- Red first, in `scripts/__tests__/plugin.test.sh:135-136`: replace the pin with the new Ask line and both
  option lines for each question. Add one grep on the update skill's `Prompt cache:` paragraph. Why: the
  recommended answer must say which costs less, and update must ask, not replay (+~3 lines).

### 6. Docs and version (~10 lines)
- `README.md:157`: `5m for main and worker panes, 1h for the relay, each with Leave as is (writes nothing)`.
- `README.md:432-434`: "only 5-minute prompt cache, main thread and subagents alike".
- `CHANGELOG.md`: new `## 0.15.0 -- 2026-10-18` section. Setup and update ask the prompt cache per role
  (5m main and workers, 1h relay, Leave as is writes nothing). Builders move from 1h to 5m. The flag values
  change: `--cache-ttl 5m|leave`, new `--relay-cache-ttl 1h|leave`. The old `recommended|default` is refused.
  The relay rewrite keeps its other `env` entries. The doctor, and setup under Needs you, warn when a TTL in the
  main checkout's `.claude/settings.local.json` would override the per-worktree answers.
- `.claude-plugin/plugin.json` 0.14.1 -> 0.15.0 (`ci/version-check.sh` needs a new number; a flag's values
  changed, so minor).

## Update on an existing install (the owner who chose 1h before)

Before: `commandeck.json` `cacheTtl: "recommended"`. The project's `.claude/settings.json` has
`promptCacheTtl: "1h"` (manifest-recorded). Each Builder worktree has `env` 1h. The relay may have its own
`env` 1h.

1. `/commandeck:update` runs `update.sh`, which replays `setup.sh` on the stored answers. `recommended` is not a
   new answer, so nothing cache-related is written or taken out. The relay's `worktree-setup.sh` rerun adds no
   TTL (no relay answer). Its `env` is untouched.
2. Setup's Needs-you block, shown by update, carries `Prompt cache: not answered since 0.15.0 ...` and, with a
   relay, `Relay prompt cache: ...`. The update skill asks those questions with the cost lines above.
3. **Leave as is** stores `leave`. Nothing changes: the 1h in `.claude/settings.json` stays, and stays
   manifest-recorded, so uninstall still takes it out. Existing Builder worktrees keep `env` 1h. Later updates
   do not ask again.
4. **5m** rewrites setup's own `promptCacheTtl` 1h to 5m. An owner-edited value stays. Each worker worktree gets
   `env` 5m at its next `worktree-setup.sh` run: `seat.sh:254` reruns it at every launch, so an existing Builder
   switches at its next seat.
5. **Relay 1h** sets the relay's TTL entry and keeps every other `env` key. **Leave as is** writes nothing.

Window: between step 1 and the answer, a new Builder gets no TTL `env` line (the hardcoded 1h is gone). It runs
on the user or project setting, or on Claude Code's default (1h on a subscription). The update skill asks in the
same session, so the window is minutes.

## Size and checks

About 115 changed lines in shipped files, plus about 40 in tests: well under 300.

Verify: `bash scripts/__tests__/install-lib.test.sh`, `worktree-setup.test.sh`, `doctor.test.sh`,
`transcript-requests.test.sh`, `plugin.test.sh` (each red before its item, green after). `bash scripts/startup-size.sh` stays green: no hook
print changes (main 9,604). `bash ci/leak-test.sh` passes, because nothing personal ships: the measurement
scripts' pane names stay out. No install or uninstall run.

## Open points for the judge

- `leave` keeps an earlier setup's 1h, as item 3 of the brief asks. The old "Leave default (takes out what an
  earlier setup wrote)" choice goes, and is not replaced. Taking it out is uninstall's job. Rejected: a third
  "Take it out" option, which nobody asked for.
- `plan-worktree-close.sh` compares a plan worktree's settings with `--print-settings`. A plan worktree made
  before the owner answers 5m differs by the new `env` line, and reads as not setup-made until
  `worktree-setup.sh` reruns. Any config answer change already behaves this way; it is not handled here.
- The cost figures are a 48-hour rerun, not the owner's exact run (the window moved). Rounded, they match the
  order's direction for every role.

## Risks and a pre-existing issue (for main to file; not in this build)

- Pre-existing issue, wider than the cache. Every key `worktree-setup.sh` writes into a worktree's own
  `.claude/settings.local.json` loses to the main checkout's `.claude/settings.local.json` wherever both set the
  same key (Facts). That covers the compact-window env, `enabledPlugins`, `disableClaudeAiConnectors`,
  `deniedMcpServers` and the relay's plugin-off map. Arrays such as `permissions.allow` merge from both files.
  Today the main checkout's local file holds only permission rules, so nothing is shadowed. This plan checks the
  TTL key only; a general check is its own unit.
- Risk. The binary counts reads of the worktree's own local file
  (`tengu_dead_probe_legacy_local_settings`), which points to a future removal. If a later Claude Code stops
  reading it, the relay 1h, the worker 5m and every other `worktree-setup.sh` setting stop applying together.
  `il_cache_ttl_report` would then still pass, because it models today's order. Watch the changelog. The
  durable home would be a flag-settings file passed at pane launch, a design change for all of
  `worktree-setup.sh`, not this unit.

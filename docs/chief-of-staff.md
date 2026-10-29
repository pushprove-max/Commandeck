# Chief of Staff

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

The Chief of Staff is a separate Claude pane that relays between you and the
orchestrator, so questions for you arrive in one place while builds run. It
reads no code and never answers for you.

When you choose one, setup creates an Orca worktree named `Chief-of-Staff`,
gives it its relay-only settings and opens the pane under the stored name.
Where it cannot (Orca does not answer, or the worktree is already there), it
ends with the exact commands left to run. The session in the main checkout is
the orchestrator and never the relay; its start-up text says where the relay
pane is, or that none exists yet. Without one, the orchestrator asks you
directly.

Setup also makes two standing worktrees, `Fast-lane` and `Research-lane`, whether or not you chose a relay, and
opens no pane in them. They are seats you work in yourself, found by folder name as the relay is, and they get the
relay's exemptions (no pane budget, your prompts logged as rulings, pickers allowed) but not its persona or watchers.
See [What each pane starts with](worker-panes.md).

The pane keeps four watchers and a timer check running in the background. Each one prints what
it found and exits, which wakes the pane:

| Watcher | Wakes the pane when |
|---|---|
| `cos-watch-inbox.sh` | the orchestrator sends it a message, or anyone sends to its own handle (checked every 20 s). A subject starting `FYI` is held and shown with the next message that does wake it, unless it was sent to its own handle |
| `cos-watch-decisions.sh` | a decision in the ledger is open and you have not been asked yet (every 20 s) |
| `cos-watch-alerts.sh` | the dashboard raises an alert for this project or the machine (every 60 s) |
| `cos-watch-limit.sh` | the 7-day usage limit reaches the threshold, 90% by default, and again for each whole percent above it |
| `cos-watch-units.sh` | a unit's worktree has a commit under a day old, its newest review round is not a GO at or after that commit, and nothing in it or its merge log changed for 12 minutes (once per commit; every 60 s). The Stop hook does not hold this one |
| `cos-check.sh` | 50 minutes pass: it names a watcher that is down, prints held FYI notes, counts messages the inbox watcher missed, and says how long you have been quiet |

A Stop hook keeps the pane from ending a turn unless all four watchers and `cos-check.sh` are alive.
To send text from a terminal, including a dictation shortcut:

```bash
bash "$PLUGIN/scripts/cos-tell.sh" 'What needs my attention?'
```

Main's durable note uses:

```bash
bash "$PLUGIN/scripts/cos-tell.sh" --note 'Build ready' 'The export unit is waiting for review.'
```

That note is stored in the orchestrator's run,
where the inbox watcher finds it even if the pane was busy, and it exits 1
when Orca does not confirm the note was stored.

The decision ledger is `.claude/metrics/decisions.jsonl` in the main
checkout. Picker questions are recorded by a hook. A plain-text question
must be entered in the ledger; a Stop hook holds an unrecorded question.
The dashboard's "Needs the owner" card reads the ledger.
`scripts/decision.sh` has add, check, answer, reopen and list operations. A
question that is still open, or was answered in the last 24 hours, cannot be
asked again without `--reask` and a line on what is new.

The ruling log is `~/.claude/rulings/<project>.jsonl`. A hook appends one row
for recognized answers, by picker or by prompt, with the time it happened
and an id. A prompt is logged only when it is typed in main's checkout or the Chief-of-Staff worktree; picker answers are logged from every pane. Slash commands and machine text (nudges, wake notices, notification blocks) are skipped. `scripts/ruling-log-archive.sh` moves older non-ruling rows into an archive file beside the log, once, deleting nothing. Agents cite that id when they write "the owner decided X", so a
decision can be traced to your words. An answer that comes back in under two
seconds is marked suspect: it may be text another pane typed into the open
picker.

## Scope of an order

A unit's scope is the owner's words and nothing else. Five rules in the relay's start-up context keep it so:
what the relay adds goes under `## Chief of Staff additions -- NOT ordered`, never in the owner's words; the
additions are offered in one multi-select question, the decoy first; a yes covers only the items it names, so
there are no bundle approvals; and at a pass-loop alert for pass 4 or more, or a class stop, the relay tells the
owner which part of the scope produces the findings and whether the owner's words asked for it. With no relay pane
running, main writes the order and keeps the same five rules (its start-up rules carry them).

An order that carries an addition is a file made from `templates/cos-order.md`: the section `## The owner's words`
first, then the NOT-ordered section. The relay writes the file only when it adds something, and runs
`scripts/cos-order-check.sh <file>` before it sends the file to main. The check exits 1 and names each fault when the
first section is not the owner's words or when a section other than the NOT-ordered one holds an addition.

The `pass-loop-<project>/<unit>-r<N>` dashboard alert is what raises the pass-4 case: it fires once for a live unit
whose newest review pass is 4 or more and NO-GO, and names the finding levels of that pass.

## Auto-decide

`/autodecide on` in the relay pane hands the owner's open decisions to the relay until `/autodecide off`. The mode
survives a restart of the pane, and only `off` ends it. While it is on, a red band above the prompt and a status-line
entry say so with the count of decisions made, the question picker is blocked in that pane (a failed guard lets the
picker through, so the owner is asked), and the system prompt carries the rules, shipped fixed as the owner wrote
them: how the owner decides (seven lines), the owner's never-decide list (one-off exceptions to their own standing
rules, plus any `autoDecideNever` entries in `.claude/commandeck.json`, added after it) and the hard limits. The
decisions ledger is not read to build them. Those limits and the list are instructions to the model; the code
checks only that the mode is on. Every time the mode shows is New York time, marked ET.

The relay makes each decision with `relay-order.sh --auto`. It writes the entry to the log first
(`.claude/metrics/autodecide-<date>.md`, with Summary, Waiting for the owner and Decisions), then records the answer
in the ledger as `<words> (auto-decided)`, marks the decision seen and tells main. Main treats a message titled
`auto-decided for the owner on <id>` as the relay's own decision, checks it against the ledger row alone (also after `off`),
and does not look for an owner ruling. The owner can reverse a decision later by answering as usual: the relay's
ordinary `relay-order.sh <id> '<words>'` replaces the auto answer and keeps it in the row's history. A send to main
that failed is resumed by the same `--auto` call again, with no second log entry. A second run started in the same
minute gets its own log (`autodecide-<date>-2.md`). `on` also adds a line for the log to `.claude/metrics/INDEX.md`.

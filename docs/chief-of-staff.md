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

The pane keeps four watchers and a timer check running in the background. Each one prints what
it found and exits, which wakes the pane:

| Watcher | Wakes the pane when |
|---|---|
| `cos-watch-inbox.sh` | the orchestrator sends it a message, or anyone sends to its own handle (checked every 20 s). A subject starting `FYI` is held and shown with the next message that does wake it, unless it was sent to its own handle |
| `cos-watch-decisions.sh` | a decision in the ledger is open and you have not been asked yet (every 20 s) |
| `cos-watch-alerts.sh` | the dashboard raises an alert for this project or the machine (every 60 s) |
| `cos-watch-limit.sh` | the 7-day usage limit reaches the threshold, 90% by default, and again for each whole percent above it |
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
and an id. Slash commands and recognized control or nudge prompts are skipped. Agents cite that id when they write "the owner decided X", so a
decision can be traced to your words. An answer that comes back in under two
seconds is marked suspect: it may be text another pane typed into the open
picker.

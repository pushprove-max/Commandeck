# Checkpoints, resume and handoff

Main is instructed to checkpoint and restart instead of compacting. Past the
clear line, a Stop hook asks for a checkpoint at
`~/.claude/checkpoints/<session-id>.md`, using `templates/checkpoint.md`: the
goal, live units, waits, queue, rulings and how to resume.
`scripts/state-snapshot.sh` fills the mechanical fields. A fresh checkpoint
is under 30 minutes old.

In Orca, the hook can open a fresh main pane, supply the resume prompt and
close the old pane after takeover. Background helpers can defer a restart;
failures leave the old pane available and write `clear-hook.log` beside the
checkpoints. This is not a guarantee that Claude Code will never compact.
Idle compaction is Claude Code's behavior, not a compactor supplied here.
The repository does not establish the runtime's exact idle-compaction version,
timeout or settings contract.

The new session starts with that checkpoint, the board, its run binding and
up to your last eight prompts word for word, under the same 10,240-byte
limit. When the block is too large it substitutes pointers or omits older
prompts, so the new session may need to read the source files. A check compares the new checkpoint with the one the
session resumed from and blocks the restart when an open item was dropped
without a reason.

The handoff skill does the same checkpoint and restart on demand, below
the line. You have to type it; the model cannot invoke it:

```text
/commandeck:handoff
```

Outside Orca the hook cannot restart the pane. It says so and asks you to
clear the session manually, and the new session does not get the resume block.

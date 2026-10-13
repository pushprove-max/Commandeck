---
name: handoff
description: Checkpoint main and restart it in a fresh pane now, below the 200K clear line. Use when the owner runs /handoff or says "hand off", "checkpoint and restart", "fresh main". Main session only.
disable-model-invocation: true
allowed-tools: Bash(bash *)
---

# /handoff

Runs the same checkpoint-and-restart main does at the 200K line
(`${CLAUDE_PLUGIN_ROOT}/templates/main-session.md`, "Main never compacts"), on demand. Main session
only: in a linked worktree `context-clear-stop.sh` ignores it.

Session id: `${CLAUDE_SESSION_ID}`. If that is not substituted, it is the
newest `*.jsonl` file name under `~/.claude/projects/<this project>/`.

Board when this skill loaded (fill the checkpoint from it; do not re-run it):

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh" 2>&1 || true
```

1. Finish the step in hand. Start nothing new.
2. Write `~/.claude/checkpoints/<session id>.md` in ONE Write from the fixed
   template `${CLAUDE_PLUGIN_ROOT}/templates/checkpoint.md`: every field filled or "none",
   live units with pane handles and task ids, what each waits on and the exact
   next command, rulings not yet in memory, the queue, the Todo list, gotchas,
   what was ruled out, how to verify, and what closed since the last checkpoint.
   Older open items are carried by a `Carries open items of: <file>` line,
   never copied. Under 5KB.
3. `touch ~/.claude/checkpoints/<session id>.handoff`
4. End the turn. Do not type `/clear`. The Stop hook opens a fresh main pane,
   closes finished panes, types the resume prompt there, and closes this pane.

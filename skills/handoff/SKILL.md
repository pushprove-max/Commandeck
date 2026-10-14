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
4. Tell the owner, in one line: "Handing off: a new main pane opens when this
   turn ends, says 'Handoff done' first, and this pane closes once it has
   taken over." Then end the turn. Do not type `/clear`, and never open a
   main pane yourself: the plugin's guard refuses a hand-made one, and the
   Stop hook is the one supported way. It opens the fresh main pane, types the
   resume prompt there, and closes this pane only after the new one has taken
   it; a step that fails leaves this pane up as main.
5. If this pane is still here at the owner's next prompt, the restart did not
   finish: a `HANDOFF NOT DONE` line names why. Read it to the owner, fix
   what it names (most often the checkpoint), and end the turn to try again.

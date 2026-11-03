# Commandeck -- Claude Code Instructions

`hooks/agent-startup-context.sh` loads `AGENT_STARTUP.md` into every
session at SessionStart. It is the canonical source for shared startup, read
gates, safety rules, implementation workflow, and git rules. Do not duplicate
those rules here.

- Never set a blanket `CLAUDE_CODE_SUBAGENT_MODEL` -- it silently downgrades
  every subagent.

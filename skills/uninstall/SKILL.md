---
name: uninstall
description: Take commandeck out of this project and put every file back as it was. Use when the owner runs /commandeck:uninstall or says "uninstall commandeck", "remove the workflow".
disable-model-invocation: true
allowed-tools: Bash(bash *), AskUserQuestion
---

# /commandeck:uninstall

1. Ask the owner one question: keep the data the plugin gathered for this
   project (cost and decision ledgers, scratch, hook log, rulings, the list of finished builds) or delete
   it. Briefs and review rounds are never touched either way.
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh`, with `--delete-data`
   when the owner said delete.
3. Show its output whole. A `changed since setup` line names a file the owner
   edited after setup: the plugin's entries are out of it, the owner's edits
   are kept, and it is not byte-for-byte what it was.
4. The machine's parts (Codex's hooks, the dashboard job, a status line setup set: the one before it comes back) go
   with the last project; the output says which projects still hold them.
5. The plugin itself is Claude Code's to remove: `claude plugin uninstall commandeck`.
   Run this skill in every project first, while the scripts are still there.

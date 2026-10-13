---
name: update
description: Finish a commandeck plugin update for this project. Use when the owner runs /commandeck:update or says "update commandeck", after `claude plugin update commandeck`.
disable-model-invocation: true
allowed-tools: Bash(bash *)
---

# /commandeck:update

Claude Code moves an updated plugin to a new folder; Codex's hooks, the
permission rule and the two background jobs still name the old one until this
runs. In each project that is set up:

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/update.sh`

It prints the version and its changelog, re-points everything, and runs the
doctor. Show the owner the changelog and any line that is not `ok`.

- It exits 1 with "back as it was" when the doctor fails: the files are
  restored; tell the owner the doctor's `FAIL` lines.
- It refuses a config version it does not know and changes nothing. There is
  no migration: the owner uninstalls with the old version, then sets up again.
- Going back a version: install the earlier version with Claude Code's
  plugin command, then run this same script from that version's folder.

---
name: doctor
description: Check the commandeck wiring for this project. Use when the owner runs /commandeck:doctor or says "is commandeck working", "check the setup", or when a Builder, a review pass, the dashboard or a wake-up does not happen.
allowed-tools: Bash(bash *)
---

# /commandeck:doctor

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` in the project. It changes
nothing, except one thing: when a newer Codex is out, it runs `codex update` and
says so (a failed update is a `warn`). Show the owner every `FAIL` and `warn` line whole: each `FAIL` ends
with the command that fixes it. Run a fix only when the owner says so, then
run the doctor again. Exit 0 means every part of the workflow can run.

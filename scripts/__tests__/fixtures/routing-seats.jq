# Seats the seat.sh tests launch that the shipped routing.json does not carry:
# a writing Codex seat, read-only Claude and Codex seats, and the pane box the
# boxed ones run in. Applied to config/routing.json, so the shipped launch
# templates and limits are the ones under test.
.launch.paneBox = "/opt/box/pane-box.sh"
| .roles += {
    companion: {agent: "codex", model: "gpt-9-sol", effort: "high", memory: "12G", sandbox: "workspace-write", edits: true},
    investigator: {agent: "claude", model: "fable", effort: "high", reviewer: true, tools: ["Edit", "Write", "NotebookEdit"], edits: false},
    "luna-reviewer": {agent: "codex", model: "gpt-9-luna", effort: "xhigh", reviewer: true, sandbox: "read-only", edits: false},
    certifier: {agent: "claude", model: "opus", effort: "high", reviewer: true, tools: ["Edit", "Write", "NotebookEdit"], edits: false}}

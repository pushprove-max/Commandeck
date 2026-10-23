# Security and privacy

Agents run on your machine, using your credentials and tool permissions.
Claude and Codex requests send prompts, code, diffs and relevant context to
their configured providers. Codex can use a provider configured in its own
config; it is not restricted here to one endpoint. Add-on installers download
code and packages and may start MCP servers or browser processes. Review their
commands in `config/addons.tsv` before applying setup.

The dashboard collector calls GitHub through gh for issues, pull requests,
milestones and checks. A local merge can create GitHub issues containing open
findings. Build-review issue drafts are filed only after your approval.
The account-usage reader uses Claude credentials from the macOS keychain or
`~/.claude/.credentials.json` to call Anthropic's usage API. Codex limit
readings and token totals come from local session records. The dashboard
collector makes no model call; the plugin does not supply a separate hosted
dashboard backend.

Local records can contain code, prompts, paths and your decisions:

| Location | Stored data |
|---|---|
| `.claude/briefs/` | Batch briefs, rendered Builder instructions, evidence and review rounds. |
| `.claude/metrics/` | Decisions, seat events, the unit ledger and helper usage. |
| `~/.commandeck/scratch/` | Per-project orchestration and temporary state. |
| `~/.commandeck/builds/`, `~/.commandeck/reviews/` | Finished-build records and HTML reviews. |
| `~/.commandeck/dashboard/` | Collected snapshots, usage caches/history, project registrations and saved layouts. |
| `~/.commandeck/install/` | Restore manifests and original configuration contents; treat backup blobs as private. |
| `~/.claude/projects/`, `~/.codex/sessions/` | Claude and Codex transcripts, under the active homes. |
| `~/.claude/checkpoints/`, `~/.claude/rulings/` | Resume checkpoints and recorded owner answers. |
| `~/.claude/hook-fire-log/` | Hook timing and action summaries. |
| `<reviewer-home>/builder-pass-prompts/` | Exact prompts used as review evidence. |

The dashboard on loopback, the default, is unauthenticated HTTP. A network bind
serves HTTPS behind a single-user login: an scrypt password hash, a
self-signed certificate, a five-failure lockout, and sessions that end on
restart. The certificate is not issued by an authority, so the first visit needs
your trust, and the login protects against other people on the network, not
against a process with your filesystem access. Host and same-origin checks are
not user authentication. Hooks and reviewer evidence deter mistakes, but a process
with your filesystem access can forge local records. The literal-secret
warning is a narrow pattern check, not a full secret scanner.

Do not publish logs or reports without reviewing them. Report vulnerabilities
privately through this repository's Security tab, as described in
[`SECURITY.md`](../SECURITY.md). Only the latest release is supported there.

How Orca's Auto permission mode meets the guard hooks, and what it leaves
unchanged, is in [`auto-permission-mode.md`](auto-permission-mode.md).

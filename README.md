<h1 align="center">Commandeck</h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.28.0-111111?style=flat-square" alt="Version 0.28.0">
  <img src="https://img.shields.io/badge/license-Apache--2.0-111111?style=flat-square" alt="Apache-2.0 license">
  <img src="https://img.shields.io/badge/runs%20on-Claude%20Code%20%2B%20Orca-111111?style=flat-square" alt="Runs on Claude Code and Orca">
</p>

---

Commandeck is a Claude Code plugin that runs on
[Orca](https://github.com/stablyai/orca). It splits agent work into three jobs.

- **Orchestrator.** One Claude session in your main checkout. It plans with
  you, launches builds and merges them. It does not write the code.
- **Builder.** One session per batch of work, in its own git worktree.
- **Reviewer.** A separate session that reads what the Builder committed.
  The merge script takes a branch only when it finds the reviewer's verdict
  for that exact commit.

You choose the work, answer decisions and push the finished commits.

![Commandeck dashboard](docs/images/dashboard.png)

The dashboard shows every Builder by stage, what waits on you, pull requests,
issues, and your Claude and Codex limits. (Sample project, invented figures.)

![Orca with Commandeck](docs/images/orca.png)

Orca with the Chief of Staff pinned, main orchestrating and one worktree per Builder.

## What you need

- [Orca](https://github.com/stablyai/orca), with its command named `orca-ide` on your `PATH`
- Claude Code 2.1.271 or later, signed in
- git, and the GitHub CLI (`gh`), signed in
- `jq`, `perl`, Python 3.11+, Bash 4+ and the GNU tools
- macOS (launchd) or Linux (systemd user services). On Windows, use WSL.

Setup checks all of this and prints the exact step for anything missing.
The full list and the details are in [docs/requirements.md](docs/requirements.md).

## Install

Add this repository as a Claude Code marketplace, then install the plugin.
Replace `<marketplace-source>` with this repository's GitHub owner/repository
or the path to a local clone.

```text
/plugin marketplace add <marketplace-source>
```

```text
/plugin install commandeck@commandeck
```

Open Claude Code in your project's primary git checkout on `main`. Then run:

```text
/commandeck:setup
```

Setup asks questions, shows a plan, and changes nothing until you choose
Apply. It never commits. Then check the wiring:

```text
/commandeck:doctor
```

Start fresh sessions after setup. More: [docs/install.md](docs/install.md)
and [docs/setup-questions.md](docs/setup-questions.md).

### Update

```bash
claude plugin update commandeck
```

Then, in each configured project:

```text
/commandeck:update
```

Update reruns setup with your saved answers and runs the doctor. If it fails,
it restores the recorded files. Start new sessions after updating.

## Use it

After setup, the Claude session in your main checkout is the orchestrator.
Tell it what you want in plain words. It writes a batch brief with you,
launches a Builder, and merges the result when the review passes. The merge is
local. Pushing is yours to do.

These are the commands you type:

| Command | Use it for |
|---|---|
| `/commandeck:setup` | First-time setup, and changing saved answers |
| `/commandeck:doctor` | Read-only check of the wiring |
| `/commandeck:update` | Repoint a project after a plugin update |
| `/commandeck:uninstall` | Remove a project's wiring |
| `/commandeck:handoff` | Save a checkpoint and restart the main session |
| `/commandeck:worktreereview <unit>` | HTML time, token and cost report for a build |

Walk-through of a first build: [docs/first-build.md](docs/first-build.md).

## Uninstall

In each configured project, while the plugin is still installed:

```text
/commandeck:uninstall
```

The skill asks whether to keep or delete the data Commandeck gathered. Then
remove the plugin:

```bash
claude plugin uninstall commandeck
```

Details: [docs/uninstall.md](docs/uninstall.md).

## More

- [Requirements](docs/requirements.md)
- [Install and update](docs/install.md)
- [What setup asks](docs/setup-questions.md)
- [Commands and skills](docs/commands.md)
- [Roles and configuration](docs/configuration.md)
- [The first build](docs/first-build.md)
- [Review passes](docs/review-loop.md)
- [Hooks](docs/hooks.md)
- [What each pane starts with](docs/worker-panes.md)
- [Chief of Staff](docs/chief-of-staff.md)
- [Cost control](docs/cost-control.md)
- [Checkpoints, resume and handoff](docs/checkpoints.md)
- [Dashboard, build review and test audit](docs/dashboard.md)
- [Fixture proof run](docs/proof-run.md)
- [Add-ons](docs/add-ons.md)
- [Layout of this repository](docs/layout.md)
- [Uninstalling](docs/uninstall.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security and privacy](docs/security.md)
- [Tests and contributing](docs/tests.md)

## Support

Best effort, no guaranteed response time. Report problems in the Issues tab
of this repository. Include the output of the command that failed, and the
output of `claude --version`. Report security vulnerabilities privately; see
[SECURITY.md](SECURITY.md).

## Licence

[Apache-2.0](LICENSE). Third-party work and add-on licences: [NOTICE](NOTICE).
What each version added: [CHANGELOG.md](CHANGELOG.md).

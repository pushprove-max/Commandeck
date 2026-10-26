# Orca's Auto permission mode and the plugin's guards

An evaluation, not a switch: nothing in the plugin or in any session's settings
changes. Orca 1.4.232 added **Manual | Auto | Yolo** under Settings, Agents
(Orca's release notes and its pull requests 30677 and 30853). The question is
whether Auto can give the orchestrator and the seats the unattended running
that skipping all permission checks gives, with fewer unchecked actions.

## What Auto is

| | Manual | Auto | Yolo |
|---|---|---|---|
| Claude Code | asks for each prompt | the agent decides routine prompts itself; Claude still checks that the model supports Auto | all permission checks skipped |
| Codex | asks for each approval | Codex's automatic reviewer decides approvals, inside its workspace sandbox | no approvals, no sandbox |
| Other agents | Manual or Yolo only, set by Orca's "Other agents" control | n/a | |

It applies to **new** sessions, terminal and native chat; a saved session keeps
the mode it had. Availability depends on the agent, the model and the host's
Orca version. Orca disables the Auto choice on a host that is too old.

## How it meets the plugin

- **The guard hooks.** Every guard in `hooks/hooks.json` is a PreToolUse hook.
  It runs before the permission decision, and a refusal from it stands whatever
  the mode: Manual, Auto or Yolo. Auto does not loosen a guard, and Yolo does not
  either. This is the property that matters: the guards, not the prompts, are
  what stop a Builder from editing main or running a long poll.
- **What Auto adds is fewer prompts**, not fewer guards. A prompt a guard already
  refuses never reaches the permission step.
- **Seat launch flags.** The plugin's Claude seat command (`launch.templates.claude`
  in `config/routing.json`) carries no permission flag: a Claude seat takes the
  mode Orca opens it with, so Auto reaches it through Orca's setting alone. A
  Codex seat carries `--sandbox` from its role (`read-only` for the Sol
  plan judge and the code reviewer) and an `--ask-for-approval` word only where a
  role sets one; none does. A read-only sandbox stays read-only under Auto,
  since Auto changes who answers an approval, not the sandbox.
- **Seats that must stay restricted** (the reviewer and the Sol judge are Codex
  with a read-only sandbox; the Fable judge is a Claude pane with the write tools denied) are unaffected by Auto for what they can write.

## What was and was not checked

Read: Orca's release notes for 1.4.232 and the two pull requests above, the
plugin's launch templates and routing roles, and the hooks' registration. **Not
probed:** a live Auto session of Claude Code or Codex in a scratch pane. The
statements about what Auto lets through come from Orca's own description, and
the statement that a PreToolUse refusal stands in every mode from Claude Code's
hook behaviour, not from a probe here. A probe should confirm each before the
owner relies on it: one guarded command (for example `sleep 400` in a Builder
pane) refused under Auto, and one ordinary command allowed.

## Recommendation

Keep Manual or the owner's current choice for main until a probe confirms the
guards refuse under Auto. Then try Auto for the orchestrator first: it keeps
every guard, asks less often than Manual, and checks more than Yolo does. Leave
the Codex judge and reviewer on their read-only sandbox. Changing any
session's permission mode is the owner's decision, so this note changes none.

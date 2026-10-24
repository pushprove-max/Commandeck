---
name: revoke
description: Take out a value setup put in this Claude profile's settings (a permission rule, an auto-mode line, the status line, a /config option), or keep the owner's own status line or option, at every launch. Use when the owner runs /commandeck:revoke.
disable-model-invocation: true
allowed-tools: Bash(bash *), AskUserQuestion
---

# /commandeck:revoke [[undo] rule <rule> | [undo] auto-mode <line> | status-line [--keep] | option <plugin> <key> [--keep] | undo status-line | undo option <plugin> <key>]

Under Orca, a launch copies the home settings file over the profile's file, and
Commandeck's session-start repair puts setup's values back. It never reads a
removal from the file, so a hand edit of setup's status line, options,
auto-mode lines or permission rules is undone at the next launch. This command
is the way to change one for good.

1. With nothing given, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revoke.sh`. It
   lists setup's values, one a line, as the command names them. Ask the owner
   which one, and whether to take it out or, for the status line or an option,
   keep the value they set themselves (`--keep`: set it first, in /config or
   the file).
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revoke.sh <what the owner chose>`,
   quoting a rule or line, and show its output whole. The file matches the
   choice now, and no pane on this profile puts setup's value back. A rerun of
   setup leaves a chosen value out too, and prints a line naming it.
3. To have setup's value back, run
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revoke.sh undo <what>`, with `<what>`
   as the listing names it. It takes the value off the list; setup's value is
   back at the next launch.

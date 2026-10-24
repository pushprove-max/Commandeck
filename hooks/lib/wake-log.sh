# Sourced by hooks that wake main or a worker through Orca: one line per attempt in the wake log (pp_wake_log).
# hook_wake_log <from> <to> <reason> <result> [error] -- paths.sh is sourced in a subshell, so a hook keeps its own shell options and
# variables; a failure to log never fails the hook.
hook_wake_log() { ( . "${BASH_SOURCE[0]%/*}/../../scripts/paths.sh" >/dev/null 2>&1 && pp_wake_log "$@" ) 2>/dev/null || true; }

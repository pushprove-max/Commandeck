# test-host-guard.sh -- loaded through BASH_ENV, never run. Issue 665, widened (main answer-1793897920-58931): bash reads
# BASH_ENV at the start of every non-interactive script, nested ones included, so a test file a script starts with a
# bare `bash <file>` is seen here, where the Bash hook (hooks/bash-guardrails.sh, the early refusal) sees only the typed
# command. On the Mac it refuses a Commandeck checkout's `__tests__/*.test.sh` started without run-shell-tests.sh's marker
# (COMMANDECK_TEST_RUNNER); that runner hands the file to the PC, or runs it here when it must. Builtins only, so every
# other script pays a path fold and one case match: no uname, no subprocess, nothing printed on a non-match, safe under set -u, and
# inert on any other host (the PC, CI). COMMANDECK_HOST_OS fakes the host in tests, as for the hook. BASH_ENV is set
# in Commandeck's tracked .claude/settings.json (issue 668), so it loads only in a Commandeck session; its value finds
# this file from any folder of the checkout. Stated limit (main's ruling msg_816ad8d781da, issue 666): a test started
# by a script through sh or zsh is not caught, since neither reads BASH_ENV; the Bash hook refuses a typed one.
case ${COMMANDECK_HOST_OS:-${OSTYPE:-}} in
  Darwin | darwin*)
    # The whole path, `./` and `//` folded, so `./x.test.sh` and `scripts/__tests__/x.test.sh` are read like a full path.
    case $0 in /*) __commandeck_t=$0 ;; *) __commandeck_t=${PWD:-}/$0 ;; esac
    while [[ $__commandeck_t == */./* || $__commandeck_t == *//* ]]; do
      __commandeck_t=${__commandeck_t//\/.\//\/}; __commandeck_t=${__commandeck_t//\/\//\/}
    done
    case $__commandeck_t in
      */__tests__/*.test.sh)
        # A Commandeck test only, by the hook's rule (bash-guardrails.sh, the Mac test block): its __tests__ folder is in
        # a checkout holding scripts/run-shell-tests.sh and Commandeck's marker, .claude-plugin/plugin.json naming
        # commandeck (issue 668: a host project's own runner, at its root or under .claude, is no checkout).
        # Read with the read builtin: no subprocess.
        __commandeck_t=${__commandeck_t%/*}
        __commandeck_m=
        if [ "${__commandeck_t##*/}" = __tests__ ] && [ -z "${COMMANDECK_TEST_RUNNER:-}" ] \
          && [ -f "${__commandeck_t%/*/*}/scripts/run-shell-tests.sh" ] && [ -f "${__commandeck_t%/*/*}/.claude-plugin/plugin.json" ]; then
          while IFS= read -r __commandeck_l || [ -n "$__commandeck_l" ]; do
            [[ $__commandeck_l =~ \"name\"[[:space:]]*:[[:space:]]*\"commandeck\" ]] && { __commandeck_m=1; break; }
          done < "${__commandeck_t%/*/*}/.claude-plugin/plugin.json"
          unset __commandeck_l
        fi
        if [ -n "$__commandeck_m" ]; then
          printf '%s\n' "BLOCKED: Commandeck tests never run on the Mac (issue 665): $0 was started without the shell test runner. Run it as \`bash scripts/run-shell-tests.sh <the file>\`, which hands it to the PC." >&2
          exit 2
        fi
        ;;
    esac
    unset __commandeck_t __commandeck_m
    ;;
esac

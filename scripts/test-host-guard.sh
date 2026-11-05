# test-host-guard.sh -- loaded through BASH_ENV, never run. Issue 665, widened (main answer-1793897920-58931): bash reads
# BASH_ENV at the start of every non-interactive script, nested ones included, so a test file a script starts with a
# bare `bash <file>` is seen here, where the Bash hook (hooks/bash-guardrails.sh, the early refusal) sees only the typed
# command. On the Mac it refuses a Commandeck checkout's `__tests__/*.test.sh` started without run-shell-tests.sh's marker
# (COMMANDECK_TEST_RUNNER); that runner hands the file to the PC, or runs it here when it must. Builtins only, so every
# other script pays a path fold and one case match: no uname, no subprocess, nothing printed on a non-match, safe under set -u, and
# inert on any other host (the PC, CI). COMMANDECK_HOST_OS fakes the host in tests, as for the hook. Main sets
# BASH_ENV in the settings env to the main checkout's copy at merge. Stated limit: a run under sh or zsh does not read
# BASH_ENV.
case ${COMMANDECK_HOST_OS:-${OSTYPE:-}} in
  Darwin | darwin*)
    # The whole path, `./` and `//` folded, so `./x.test.sh` and `scripts/__tests__/x.test.sh` are read like a full path.
    case $0 in /*) __commandeck_t=$0 ;; *) __commandeck_t=${PWD:-}/$0 ;; esac
    while [[ $__commandeck_t == */./* || $__commandeck_t == *//* ]]; do
      __commandeck_t=${__commandeck_t//\/.\//\/}; __commandeck_t=${__commandeck_t//\/\//\/}
    done
    case $__commandeck_t in
      */__tests__/*.test.sh)
        # A Commandeck test only, by the hook's rule (bash-guardrails.sh:489): its __tests__ folder is in a checkout
        # holding scripts/run-shell-tests.sh. The settings give every project this BASH_ENV; other projects' tests run.
        __commandeck_t=${__commandeck_t%/*}
        if [ "${__commandeck_t##*/}" = __tests__ ] && [ -f "${__commandeck_t%/*/*}/scripts/run-shell-tests.sh" ] \
          && [ -z "${COMMANDECK_TEST_RUNNER:-}" ]; then
          printf '%s\n' "BLOCKED: Commandeck tests never run on the Mac (issue 665): $0 was started without the shell test runner. Run it as \`bash scripts/run-shell-tests.sh <the file>\`, which hands it to the PC." >&2
          exit 2
        fi
        ;;
    esac
    unset __commandeck_t
    ;;
esac

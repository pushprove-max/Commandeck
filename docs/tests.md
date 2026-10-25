# Tests

From a clone, list or run the ordinary shell suite:

```bash
bash scripts/run-shell-tests.sh --list
bash scripts/run-shell-tests.sh
```

The runner covers top-level shell tests in `hooks/__tests__/` and
`scripts/__tests__/`. Parked tests are reported as skipped. Tests marked
own-lane are skipped by the ordinary run and have a separate mode:

```bash
bash scripts/run-shell-tests.sh --own-lane
```

For a focused check, compare to `main` from a branch:

```bash
bash scripts/run-shell-tests.sh --changed main
```

This selects edited tests and same-name tests for changed scripts or hooks;
it does not discover every caller of a shared helper. With no base argument,
the base is HEAD. Documentation changes select no shell tests.

Add `--callers` to also select every test that names a changed script or hook
by its file name, and the tests that name those tests, until nothing new turns
up (`scripts/shell-tests-for.sh` does the selecting; a shared helper selects
many tests):

```bash
bash scripts/run-shell-tests.sh --changed main --callers
```

To know whether a test file needs a new run, ask what it reads. It prints
`unchanged <file>` when neither the file, nor a script it names, nor a file those
source has changed since the commit, and `changed <file>` otherwise (or when it
cannot tell):

```bash
bash scripts/test-inputs.sh <commit> <test file>...
```

The other repository checks are:

```bash
bash ci/leak-test.sh
bash ci/version-check.sh
claude plugin validate .
bash scripts/startup-size.sh
```

Version check compares to `origin/main` by default. Documentation-only changes
need no version bump. Plugin changes need a version and changelog entry; see
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

Use the runtime requirements above plus ripgrep and Node.js. Dashboard DOM
tests need jsdom 26. CI installs it into a temporary prefix and supplies the
path rather than adding a project dependency. To match that locally:

```bash
COMMANDECK_TEST_DEPS=$(mktemp -d)
npm install --prefix "$COMMANDECK_TEST_DEPS" --no-save jsdom@26
COMMANDECK_TEST_NODE_MODULES="$COMMANDECK_TEST_DEPS/node_modules" bash scripts/run-shell-tests.sh
```

The runner needs Bash 4+ and GNU tools. CI uses Ubuntu's jq 1.7; verify against
that version when changing jq programs. Test concurrency and per-file timeout
can be set with `COMMANDECK_SHELL_TEST_JOBS` and
`COMMANDECK_SHELL_TEST_TIMEOUT`. Defaults are half the CPUs (at least one)
and 120 seconds, except a test's own timeout marker.

Contributions should branch from `main`, keep one change per pull request,
and add a test that fails without a behavior fix. Open an issue first for a
larger change. Follow the repository's contributing instructions; do not add
whole-install tests for new behavior. The fixture proof is a separate manual check described in [Numbers](proof-run.md).

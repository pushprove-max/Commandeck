# Contributing

## Bugs and feature requests

Open an issue and pick the bug report or feature request template.

## Running the checks

CI runs two commands from the repository root:

```bash
bash ci/leak-test.sh
bash scripts/run-shell-tests.sh
```

They need `bash`, `git`, `ripgrep`, `jq` and `perl`. The dashboard's DOM tests
also need `jsdom` 26, installed with `npm`; `COMMANDECK_TEST_NODE_MODULES` is
the `node_modules` folder it lands in.

## Pull requests

This project does not accept pull requests from outside for now. Bug
reports and feature requests are welcome as issues; if you have a fix in
mind, describe it there.

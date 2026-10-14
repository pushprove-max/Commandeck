# Contributing

## Bugs and feature requests

Open an issue and pick the bug report or feature request template.

## Running the checks

CI runs three commands from the repository root:

```bash
bash ci/leak-test.sh
bash ci/version-check.sh
bash scripts/run-shell-tests.sh
```

Every change to the plugin raises the version in `.claude-plugin/plugin.json` and the README's badge, with a `CHANGELOG.md` entry: the third part for a fix, the second for new behaviour.
`ci/version-check.sh` fails when a plugin file changed against the main branch and the version did not; a change to the docs or to `ci/` alone does not count.

They need `bash`, `git`, `ripgrep`, `jq` and `perl`.

## Pull requests

This project does not accept pull requests from outside for now. Bug
reports and feature requests are welcome as issues; if you have a fix in
mind, describe it there.

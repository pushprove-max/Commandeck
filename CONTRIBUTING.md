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

Pull requests are welcome. For anything larger than a small fix, open an issue first so we can agree on the
approach.

- Branch from `main` and keep each pull request to one change.
- Run the three checks above; CI runs them on every pull request.
- A change to a plugin file raises the version and adds a `CHANGELOG.md` entry, as described above.
- Add a test that fails without your change. Keep it to the function or rule your change touches, on a hand-written
  config. No test installs or uninstalls the plugin, or runs `setup.sh` or `uninstall.sh` whole.
- Pull requests are squash-merged. A maintainer reviews each one, and CI for a first-time contributor runs after
  a maintainer approves it.

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

To run the shell tests before each push to `main`, wire the pre-push hook once in your checkout: `git config core.hooksPath .githooks`. A red run refuses the push and names the commit.

Every change to the plugin raises the version in `.claude-plugin/plugin.json` and the README's badge, with a `CHANGELOG.md` entry: the third part for a fix, the second for new behaviour.
`ci/version-check.sh` fails when a plugin file changed against the main branch and the version did not; a change to the docs or to `ci/` alone does not count.

A `CHANGELOG.md` entry is a release note, written for the person who uses the plugin:
- Put it under `## <x.y.z> -- <date>` as `###` topics named for what a person does or sees, with no intro paragraph. Anything the person must do goes first, under `### What you need to do`; security fixes go under `### Security and maintenance`.
- Each bullet is one or two plain sentences saying what changed, the effect first.
- Never name a file, script, function or path, or give an issue number, "Closes", a commit hash or an internal unit name. A slash command, a setup question or a setting name the person types or sees is fine.
- `bash scripts/release-notes.sh --check` prints each line that breaks this and exits 1; it must exit 0 before you send a change. The release job runs the same check on the entry it publishes.

They need `bash`, `git`, `ripgrep`, `jq` and `perl`.
CI's Ubuntu ships jq 1.7, which refuses some programs jq 1.8 accepts: before you send a change, run the suite once
with jq 1.7 first on `PATH` (on a Mac, `J=$(mktemp -d); ln -s /usr/bin/jq "$J/jq"; PATH="$J:$PATH" bash scripts/run-shell-tests.sh`).

The local merge check runs only the shell tests a change touches: `bash scripts/run-shell-tests.sh --changed main`
from your branch. CI and anyone who wants the whole suite run `bash scripts/run-shell-tests.sh`, which starts the
slowest files first from the seconds it saved on earlier bare runs.

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

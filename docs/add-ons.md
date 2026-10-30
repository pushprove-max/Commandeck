# Add-ons

Setup's default is to attempt the add-ons listed in `config/addons.tsv`.
Commands with installers install or update to latest; no version is pinned.
Entries that say to see an upstream installer page need manual installation.

Selecting specific add-ons or None limits **that setup run**. The selection
is not saved, so a later setup or update without a selection attempts the
default list. Setup prints failures under Needs you and prints commands for
anything it did not install. A successful setup message does not mean every
add-on succeeded.

| Add-on | What it adds | Local cost or setup behavior |
|---|---|---|
| serena | Symbol lookup | Language-server processes; selecting it enables its hook setting unless explicitly disabled. With it on, each worktree runs one shared Serena server on 127.0.0.1 (`scripts/serena-shared.sh`); seats and review passes use it, and closing the worktree stops it. |
| agent-browser | Browser automation | Global npm package and a browser download. |
| ui-themes | Theme skills | Installed by a plugin command; loaded when requested. |
| Engineering-skills add-on | Engineering skills | No one-line installer in this registry; skill descriptions add session context. |

Upstream sources and recorded licences are in [`NOTICE`](../NOTICE). That file's
older statement that setup only prints add-on commands is stale; the current
`setup.sh` and `config/addons.tsv` determine installation behavior. Uninstall
does not remove external add-ons or undo their updates.

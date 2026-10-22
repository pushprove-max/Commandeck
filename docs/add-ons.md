# Add-ons

Setup's default is to attempt the add-ons listed in `config/addons.tsv`.
Commands with installers install or update to latest; no version is pinned.
Entries that say to see an upstream installer page need manual installation.
The full Ponytail plugin is attempted by default only if already enabled and
the setup Ponytail answer is on. The bundled Ponytail skill is separate,
on by default and never overwrites an existing copy.

Selecting specific add-ons or None limits **that setup run**. The selection
is not saved, so a later setup or update without a selection attempts the
default list. Setup prints failures under Needs you and prints commands for
anything it did not install. A successful setup message does not mean every
add-on succeeded.

| Add-on | What it adds | Local cost or setup behavior |
|---|---|---|
| serena | Symbol lookup | Language-server processes; selecting it enables its hook setting unless explicitly disabled. |
| codebase-memory | Repository graph | Background indexer and MCP tools; manual first install, then guarded updates and a tool-list check. |
| agent-browser | Browser automation | Global npm package and a browser download. |
| ponytail, full plugin | Startup coding rules | Separate from the bundled on-demand skill; its registry description estimates about 1 KB of rules. |
| ui-themes | Theme skills | Installed by a plugin command; loaded when requested. |
| Engineering-skills add-on | Engineering skills | No one-line installer in this registry; skill descriptions add session context. |

Upstream sources and recorded licences are in [`NOTICE`](../NOTICE). That file's
older statement that setup only prints add-on commands is stale; the current
`setup.sh` and `config/addons.tsv` determine installation behavior. Uninstall
does not remove external add-ons or undo their updates.

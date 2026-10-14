#!/usr/bin/env bash
# update.sh -- run from the plugin's NEW folder after `claude plugin update`,
# in the project. Claude Code moves the plugin to a new versioned folder, and
# what setup wrote outside it still names the old one: Codex's hook entries and
# their trust, the permission rule for the scripts, the two jobs. This prints
# the version and its changelog, runs setup again with the answers already in
# the project's config, and runs the doctor. If the doctor fails, every file is
# put back as it was before the update and this exits 1.
# A config whose version this plugin does not know is refused: there is no
# migration code.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/paths.sh"
. "$HERE/install-lib.sh"
die() { echo "update: $*" >&2; exit 1; }
[ -e "$IL_CONFIG" ] || die "$PP_MAIN is not set up; run: bash $(printf '%q' "$HERE")/setup.sh --profile claude|claude-openai"
V=$(jq -r '.version // "(none)"' "$IL_CONFIG" 2>/dev/null) || V="(unreadable)"
[ "$V" = "$IL_VERSION" ] || die "$IL_CONFIG is config version $V, and this plugin knows version $IL_VERSION only. Nothing was changed. It does not migrate a config: uninstall with the plugin version that wrote it, then set up again."
[ -s "$IL_PROJECT" ] || die "no install manifest for $PP_MAIN ($IL_PROJECT); run setup.sh instead"

echo "commandeck $(jq -r .version "$IL_ROOT/.claude-plugin/plugin.json") at $IL_ROOT (was at $(jq -r '.root // "?"' "$IL_PROJECT"))"
awk '/^## / { n++ } n == 1' "$IL_ROOT/CHANGELOG.md"

# Every recorded path as it is now, for the way back, and the Codex home in
# use today: setup writes to it, and it is not on record yet if it is a new one.
# The dashboard's view and project list are in no manifest (dashboard.sh writes
# them): a new view left beside the old configuration is half an update.
DASH_DIR=${COMMANDECK_DASHBOARD_DIR:-$HOME/.commandeck/dashboard}
DASH_FILES=("$DASH_DIR/index.html" "$DASH_DIR/app.css" "$DASH_DIR/app.js" "$DASH_DIR/projects")
KEEP=$(mktemp -d); trap 'rm -rf "$KEEP"' EXIT
mapfile -t PATHS < <(jq -r '.entries | to_entries[] | select(.value.kind != "dir") | .key' "$IL_PROJECT" "$IL_MACHINE" 2>/dev/null; printf '%s\n' "$IL_PROJECT" "$IL_MACHINE" "$IL_CODEX/hooks.json" "$IL_CODEX/config.toml" "${DASH_FILES[@]}")
# A link to a file not made yet is the owner's: setup writes through it, and
# the way back removes what it wrote and leaves the link.
for i in "${!PATHS[@]}"; do
  # A link to a folder (the stable plugin link) is kept as the link: cp would copy the folder.
  if [ -L "${PATHS[$i]}" ] && [ -d "${PATHS[$i]}" ]; then readlink "${PATHS[$i]}" > "$KEEP/$i.dirlink"
  elif [ -e "${PATHS[$i]}" ]; then cp -p "${PATHS[$i]}" "$KEEP/$i"; elif [ -L "${PATHS[$i]}" ]; then : > "$KEEP/$i.link"; fi
done
back() {
  for i in "${!PATHS[@]}"; do
    # A file kept read-only refuses the copy; it gets its mode back from the copy.
    if [ -e "$KEEP/$i.dirlink" ]; then ln -sfn "$(cat "$KEEP/$i.dirlink")" "${PATHS[$i]}"
    elif [ -e "$KEEP/$i" ]; then [ ! -e "${PATHS[$i]}" ] || [ -w "${PATHS[$i]}" ] || chmod u+w "${PATHS[$i]}"; cp -p "$KEEP/$i" "${PATHS[$i]}"
    elif [ -e "$KEEP/$i.link" ]; then [ ! -e "${PATHS[$i]}" ] || rm -f "$(readlink -f "${PATHS[$i]}")"
    else rm -f "${PATHS[$i]}"; fi
  done
  echo "update: FAILED ($1). Every file is back as it was before the update; the two jobs were restarted by the failed run and may need: bash $(jq -r '.root // "<old plugin folder>"' "$IL_PROJECT")/scripts/setup.sh" >&2
  exit 1
}
bash "$HERE/setup.sh" >/dev/null || back "setup did not finish"
bash "$HERE/doctor.sh" || back "the doctor found a break, above"
echo "update: done"

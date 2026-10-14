#!/bin/sh
# run-hook.sh <hook file> [args] -- every hook is started through this file.
# The hooks need Bash 4 or newer, and some do not even parse under the Mac's
# own Bash 3.2: started by it each one failed, and a hook that fails blocks the
# command it guards. This file is plain sh, so that Bash can read it. It finds
# a Bash 4 or newer, in Homebrew's places and then on PATH, and runs the hook
# under it; it never reads standard input, so the hook gets its payload
# untouched. With none found it says so in one line and exits 0: no hook ran,
# and nothing is blocked. COMMANDECK_BREW_PREFIX relocates Homebrew for the
# self-test.
for b in "${COMMANDECK_BREW_PREFIX:-/opt/homebrew}/bin/bash" "${COMMANDECK_BREW_PREFIX:-/usr/local}/bin/bash" bash; do
  b=$(command -v "$b" 2>/dev/null) || continue
  # The same question also reads the PATH the scripts give themselves on a Mac
  # (req_path: Homebrew's GNU tools ahead of the system's), for the hook to get.
  p=$("$b" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ] || exit 1; [ ! -r "$0" ] || . "$0"; printf %s "$PATH"' "$(dirname "$0")/../../scripts/requirements.sh" </dev/null 2>/dev/null) || continue
  [ -z "$p" ] || { PATH=$p; export PATH; }
  exec "$b" "$@"
done
echo "commandeck: no Bash 4 or newer on this machine, so this plugin's hooks did not run and checked nothing. /commandeck:setup can install it (on a Mac: brew install bash)."
exit 0

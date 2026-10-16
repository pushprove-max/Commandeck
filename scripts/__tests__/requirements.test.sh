#!/usr/bin/env bash
# requirements.test.sh -- on a fresh Mac setup stopped on the first missing tool, named one at a time, and told the
# owner to edit a shell start file. What this pins: one check names everything missing at once, in two groups (what
# a package manager can install, with the one command; what only the owner can do, with its step); nothing is
# installed without --install-missing, and with it the printed command runs once and setup carries on in the same
# run; and a script the Mac's Bash 3.2 started carries on under Homebrew's, once, with its arguments and input.
# Every setup.sh run here stops at the requirements check or at its own argument check, before it writes
# anything: no run of setup.sh goes further.
# No package is installed: brew, apt-get and sudo are stand-ins that record their arguments, on a PATH that holds
# nothing but the test's folders. The Bash 3.2 cases need the Mac's own /bin/bash; where there is none they are
# printed as not run (CI runs them in its macOS job).
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
BIN=$T/bin PLUGIN=$T/plugin PROJ=$T/proj
mkdir -p "$HOME" "$BIN" "$PLUGIN"
# A copy outside any checkout: the Bash 3.2 cases add a probe script to it.
for d in scripts config templates hooks; do cp -R "$SOURCE/$d" "$PLUGIN/"; done
git init -q -b main "$PROJ"
. "$SOURCE/scripts/requirements.sh"
NEW=$BASH
printf '#!/usr/bin/env bash\ncase "$*" in *--help*) echo worktree ;; *) echo "{\\"ok\\":true}" ;; esac\n' > "$BIN/orca-ide"
printf '#!/usr/bin/env bash\n[ "$*" != "auth token" ] || exit 0\n' > "$BIN/gh"
printf '#!/usr/bin/env bash\n[ "$*" = "login status" ]\n' > "$BIN/codex"
# Every tool on this machine, as links in one folder, so that taking one out makes it missing.
FARM=$T/farm; mkdir -p "$FARM" "$HOME/.local/bin" "$T/nobrew" "$T/brew/bin" "$T/keep"
IFS=: read -ra DIRS <<<"$PATH"
for d in "${DIRS[@]}"; do [ ! -d "$d" ] || ln -s "$d"/* "$FARM/" 2>/dev/null; done
for t in sed stat date readlink grep; do [ -e "$FARM/g$t" ] || ln -s "$(command -v "$t")" "$FARM/g$t"; done
rm -f "$FARM"/{orca-ide,orca,gh,codex,claude,brew,apt-get,sudo,systemctl,pgrep}
OS=Linux BREW=$T/nobrew
# go <script> [args] -- a plugin script in the project, on the scratch PATH alone.
go() {
  ( cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u CODEX_HOME -u COMMANDECK_DASHBOARD_DIR \
      -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_ROUTING PATH="$BIN:$FARM" COMMANDECK_BREW_PREFIX="$BREW" COMMANDECK_HOST_OS="$OS" "${SHELL_UNDER_TEST:-$NEW}" "$PLUGIN/scripts/$1" "${@:2}" </dev/null )
}
# group <name> -- that group's lines of the last output, without the other's.
group() { awk -v g="$1" '/^(can install|yours to do)/ { on = index($0, g) == 1 } on' "$T/out"; }
printed() { group 'can install' | sed -n 's/^  //p'; }
snap() { (cd "$T" && find home proj -path '*/.git/*' -prune -o -print | sort); }
printf '#!/bin/sh\nprintf "sudo " >> %q\nexec "$@"\n' "$T/pm" > "$BIN/sudo"
printf '#!/bin/sh\necho "apt-get $*" >> %q\n[ ! -e %q ] || ln -s %q %q %q/\n' "$T/pm" "$T/pm-works" "$(command -v jq)" "$(command -v flock)" "$BIN" > "$BIN/apt-get"
printf '#!/bin/sh\necho "brew $*" >> %q\n[ ! -e %q ] || ln -s %q %q/bash\n' "$T/pm" "$T/pm-works" "$NEW" "$T/brew/bin" > "$T/keep/brew"
chmod +x "$BIN"/* "$T/keep/brew"
BEFORE=$(snap)

# --- three things missing: one message, two groups, one command, nothing run ---
rm "$FARM/jq" "$FARM/flock"; mv "$BIN/orca-ide" "$T/keep/"
go setup.sh --profile claude-openai --name Ada >"$T/out" 2>&1; check "setup stops when requirements are missing" 1 $?
check "the two tools a package manager supplies are in the installable group" '1 1' "$(group 'can install' | head -1 | grep -c 'jq') $(group 'can install' | head -1 | grep -c 'flock')"
check "with the one command for this machine" 'sudo apt-get install -y util-linux jq' "$(printed)"
check "Orca is the owner's to do, named with its address" 1 "$(group 'yours to do' | grep -c "orca-ide.*Orca (https://github.com/stablyai/orca).*\.deb.*https://github.com/stablyai/orca/releases")"
check "and not in the installable group" 0 "$(group 'can install' | grep -ci orca)"
check "nothing was installed without the flag" 0 "$([ -e "$T/pm" ] && echo 1 || echo 0)"
check "and nothing on the machine changed" "$BEFORE" "$(snap)"
WANT=$(printed)
# A value is never a flag: an option missing its value does not turn --install-missing into the owner's yes.
BAD=
for o in --builder-effort --builder-clear-line --issue-sizing --addons --cache-ttl --own-startup --own-main-session --rules --rules-drop --rules-keep --max-rounds --closing-pass --small-build --max-review-min --max-test-percent --max-usd --review-flags; do
  go setup.sh --profile claude "$o" --install-missing >"$T/out" 2>&1
  [ ! -e "$T/pm" ] || { BAD+=" $o"; rm "$T/pm"; }
done
check "an option given --install-missing as its value installs nothing" '' "$BAD"
# A plan writes nothing, so it installs nothing either.
go setup.sh --profile claude --plan --install-missing >"$T/out" 2>&1
check "a plan with --install-missing installs nothing" 1:0 "$?:$([ -e "$T/pm" ] && echo 1 || echo 0)"
# The decoy's pause starts only once --questions begin has passed its checks.
go setup.sh --questions begin >"$T/out" 2>&1
check "a --questions begin that stops on a missing requirement leaves the decoy on" '1:gone' "$?:$([ -e "$PROJ/.git/commandeck-setup-questions" ] || echo gone)"

mv "$T/keep/orca-ide" "$BIN/"
# --- an install that works: setup carries on in the same run, to its own argument check ---
touch "$T/pm-works"
go setup.sh --profile nonsense --install-missing >"$T/out" 2>&1
check "after an install that supplies everything setup carries on, having run the printed command once" "2:$WANT" "$?:$(cat "$T/pm" 2>/dev/null)"
check "and nothing on the machine changed" "$BEFORE" "$(snap)"
rm -f "$T/pm"

# --- Bash 3.2 on a Mac: carry on under Homebrew's, once ---
OS=Darwin BREW=$T/brew
check "requirements.sh keeps to Bash 3.2's syntax" 0 "$(/bin/bash -n "$SOURCE/scripts/requirements.sh" 2>&1 | grep -c .)"
if [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" -ge 4 ]; then
  echo "NOT RUN here (no Bash 3 at /bin/bash): the six restart cases; CI's macOS job runs them"
else
  SHELL_UNDER_TEST=/bin/bash
  printf 'shift\n. "$(dirname "$0")/paths.sh" || exit 9\necho "${BASH_VERSINFO[0]}"; printf "<%%s>" "$@"; cat\n' > "$PLUGIN/scripts/probe.sh"
  # The stand-in for Homebrew's Bash is the real newer one, and counts each script it is given.
  newer() { printf '#!/bin/sh\ncase $1 in -c) exec %q "$@" ;; esac\necho "$*" >> %q\nexec %q "$@"\n' "$NEW" "$T/restarts" "$1" > "$T/brew/bin/bash"; chmod +x "$T/brew/bin/bash"; }
  newer "$NEW"
  OUT=$(printf 'in\n' | { cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR PATH="$BIN:$FARM" COMMANDECK_BREW_PREFIX="$BREW" COMMANDECK_HOST_OS=Darwin /bin/bash "$PLUGIN/scripts/probe.sh" a 'b c' '' 2>&1; })
  check "a script started by Bash 3 runs under the newer one, with every argument it was started with and its input" "${BASH_VERSINFO[0]} <b c><>in" "$(echo $OUT)"
  check "started again once" 1 "$(grep -c . "$T/restarts")"
  rm -f "$T/restarts"
  go setup.sh --profile nonsense >"$T/out" 2>&1; check "setup.sh started by Bash 3 reaches its own argument check under the newer one" 2 $?
  check "started again once, with its arguments" "$PLUGIN/scripts/setup.sh --profile nonsense" "$(cat "$T/restarts" 2>/dev/null)"
  # A "newer" Bash that starts scripts under Bash 3 after all: no second restart.
  rm -f "$T/restarts"; newer /bin/bash
  go setup.sh --profile nonsense >"$T/out" 2>&1; check "a restart that lands in Bash 3 again fails" 1 $?
  check "after one restart, not a loop" 1 "$(grep -c . "$T/restarts")"
  check "with the check's message" 1 "$(grep -c 'Bash 4 or newer' "$T/out")"
  # No Homebrew Bash at all: the check's message, with the command; and on a yes setup installs it and carries on under it.
  rm -f "$T/restarts" "$T/brew/bin/bash" "$T/pm"; cp "$T/keep/brew" "$BIN/brew"
  go setup.sh --profile nonsense >"$T/out" 2>&1; check "Bash 3 and no Homebrew Bash: setup stops" 1 $?
  check "with the check's message and its one command" 'brew install bash' "$(printed)"
  go setup.sh --profile nonsense --install-missing >"$T/out" 2>&1
  check "on a yes it installs Bash and carries on under it, to its own argument check" "2 brew install bash" "$? $(cat "$T/pm" 2>/dev/null)"
  # What Homebrew installs lands in a gnubin folder that was not there when setup started: PATH is read again.
  rm -f "$T/pm" "$BIN/flock"
  printf '#!/bin/sh\necho "brew $*" >> %q\nmkdir -p %q && ln -s %q %q/\n' "$T/pm" "$T/brew/opt/flock/libexec/gnubin" "$(command -v flock)" "$T/brew/opt/flock/libexec/gnubin" > "$BIN/brew"
  go setup.sh --profile nonsense --install-missing >"$T/out" 2>&1
  check "a tool Homebrew put in a new folder is found by the check that follows the install" "2 brew install flock" "$? $(cat "$T/pm" 2>/dev/null)"
  rm -f "$PLUGIN/scripts/probe.sh"
fi

[ "$FAIL" = 0 ] || { echo "--- last output"; tail -15 "$T/out"; }
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

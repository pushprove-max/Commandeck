#!/usr/bin/env bash
# timeout: 300 -- one full setup among many refused ones
# setup-requirements.test.sh -- on a fresh Mac setup stopped on the first
# missing tool, named one at a time, and told the owner to edit a shell start
# file. What this pins: one check names everything missing at once, in two
# groups (what a package manager can install, with the one command; what only
# the owner can do, with its step); nothing is installed without
# --install-missing, and with it exactly the printed command runs, once; a
# second look that still finds something missing stops with nothing changed;
# the doctor reports the same set; Orca's own command is linked as orca-ide
# only on a yes and only when it really is Orca's; and a script the Mac's Bash
# 3.2 started carries on under Homebrew's, once, with its arguments and input.
# No package is installed: brew, apt-get and sudo are stand-ins that record
# their arguments, on a PATH that holds nothing but the fixture's folders.
# The Bash 3.2 cases need the Mac's own /bin/bash; where there is none they
# are printed as not run (CI runs them in its macOS job).
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
. "$SOURCE/scripts/requirements.sh"
NEW=$BASH
# Every tool on this machine, as links in one folder, so that taking one out makes it missing.
FARM=$T/farm; mkdir -p "$FARM" "$HOME/.local/bin" "$T/nobrew" "$T/brew/bin" "$T/keep"
IFS=: read -ra DIRS <<<"$PATH"
for d in "${DIRS[@]}"; do [ ! -d "$d" ] || ln -s "$d"/* "$FARM/" 2>/dev/null; done
for t in sed stat date readlink grep; do [ -e "$FARM/g$t" ] || ln -s "$(command -v "$t")" "$FARM/g$t"; done
rm -f "$FARM"/{orca-ide,orca,gh,codex,claude,brew,apt-get,sudo,systemctl,pgrep}
OS=Linux BREW=$T/nobrew MORE=
# go <script> [args] -- a plugin script in the project, on the scratch PATH alone.
go() {
  ( cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u CODEX_HOME -u COMMANDECK_DASHBOARD_DIR \
      -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_ROUTING PATH="$BIN:$FARM$MORE" COMMANDECK_BREW_PREFIX="$BREW" COMMANDECK_HOST_OS="$OS" "${SHELL_UNDER_TEST:-$NEW}" "$PLUGIN/scripts/$1" "${@:2}" </dev/null )
}
# group <name> -- that group's lines of the last output, without the other's.
group() { awk -v g="$1" '/^(can install|yours to do)/ { on = index($0, g) == 1 } on' "$T/out"; }
printed() { group 'can install' | sed -n 's/^  //p'; }
printf '#!/bin/sh\nprintf "sudo " >> %q\nexec "$@"\n' "$T/pm" > "$BIN/sudo"
printf '#!/bin/sh\necho "apt-get $*" >> %q\n[ ! -e %q ] || ln -s %q %q %q/\n' "$T/pm" "$T/pm-works" "$(command -v jq)" "$(command -v flock)" "$BIN" > "$BIN/apt-get"
printf '#!/bin/sh\necho "brew $*" >> %q\n[ ! -e %q ] || ln -s %q %q/bash\n' "$T/pm" "$T/pm-works" "$NEW" "$T/brew/bin" > "$T/keep/brew"
chmod +x "$BIN/sudo" "$BIN/apt-get" "$T/keep/brew"
BEFORE=$(snap)

# --- three things missing: one message, two groups, one command, nothing run ---
rm "$FARM/jq" "$FARM/flock"; mv "$BIN/orca-ide" "$T/keep/"
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup stops when requirements are missing" 1 $?
check "the two tools a package manager supplies are in the installable group" '1 1' "$(group 'can install' | head -1 | grep -c 'jq') $(group 'can install' | head -1 | grep -c 'flock')"
check "with the one command for this machine" 'sudo apt-get install -y util-linux jq' "$(printed)"
check "Orca is the owner's to do, named with its address" 1 "$(group 'yours to do' | grep -c "orca-ide.*Orca (https://github.com/stablyai/orca).*\.deb.*https://github.com/stablyai/orca/releases")"
check "and not in the installable group" 0 "$(group 'can install' | grep -ci orca)"
check "the old one-line refusal is gone" 0 "$(grep -c 'missing on PATH' "$T/out")"
check "nothing was installed without the flag" 0 "$([ -e "$T/pm" ] && echo 1 || echo 0)"
check "and nothing on the machine changed" "$BEFORE" "$(snap)"
WANT=$(printed)
# The yes is the flag itself. A value that spells it (a relay named --install-missing) is a value.
VALUED=$(grep -oE '^ +--profile\|[a-z|-]+\) \[ \$# -ge 2' "$PLUGIN/scripts/setup.sh" | sed 's/).*//' | tr -d ' ' | tr '|' ' ')
for o in $VALUED; do go setup.sh --profile claude "$o" --install-missing >"$T/out" 2>&1; done
check "setup has options that take a value" 1 "$([ "$(wc -w <<<"$VALUED")" -ge 11 ] && echo 1 || echo 0)"
check "the flag's spelling as the value of any of them installs nothing" 0 "$([ -e "$T/pm" ] && echo 1 || echo 0)"

# --- the doctor names the same set for the same PATH ---
grep -E '^(can install|yours to do|  )' "$T/out" > "$T/setup-set"
go doctor.sh >"$T/out" 2>&1; check "the doctor fails on the same PATH" 1 $?
check "with one FAIL line for the tools" 1 "$(grep -c '^FAIL tools' "$T/out")"
check "and the same missing set as setup, word for word" "$(cat "$T/setup-set")" "$(grep -E '^(can install|yours to do|  )' "$T/out")"
OS=Darwin go doctor.sh >"$T/out" 2>&1
check "on a Mac the doctor names the tools, not a missing project" '1 0' "$(grep -c '^FAIL tools' "$T/out") $(grep -c 'not in a project' "$T/out")"

# --- --install-missing: the printed command, once; still missing means stop, nothing changed ---
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1; check "an install that leaves something missing stops setup" 1 $?
check "it ran exactly the printed command, once" "$WANT" "$(cat "$T/pm" 2>/dev/null)"
check "and changed nothing else" "$BEFORE" "$(snap)"
rm -f "$T/pm"; mv "$BIN/apt-get" "$T/keep/"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1; check "with no package manager setup stops" 1 $?
check "it runs nothing" 0 "$([ -e "$T/pm" ] && echo 1 || echo 0)"
check "and names what is missing as the owner's to install" 1 "$(group 'yours to do' | grep -c 'flock, jq: there is no apt-get')"
check "with nothing offered to install" 0 "$(grep -c '^can install' "$T/out")"

# --- a Mac: Homebrew's command, and never Homebrew itself ---
OS=Darwin; cp "$T/keep/orca-ide" "$BIN/"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1; check "a Mac without Homebrew: setup stops" 1 $?
check "Homebrew is the owner's to install, with what it supplies" 1 "$(group 'yours to do' | grep -c 'Homebrew: it is not installed, and it supplies flock, jq\. .*https://brew.sh')"
check "and nothing was run" 0 "$([ -e "$T/pm" ] && echo 1 || echo 0)"
cp "$T/keep/brew" "$BIN/brew"
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "with Homebrew the command is one brew install" 'brew install flock jq' "$(printed)"
check "not run without the flag" 0 "$([ -e "$T/pm" ] && echo 1 || echo 0)"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1
check "with the flag: that command, once" 'brew install flock jq' "$(cat "$T/pm" 2>/dev/null)"
check "nothing tells the owner to edit a shell start file or reorder PATH" 0 "$(grep -ciE 'first on PATH|zshrc|bash_profile|bashrc|\.profile' "$T/out")"
OS=Linux; rm -f "$T/pm" "$BIN/brew" "$BIN/orca-ide"; mv "$T/keep/apt-get" "$BIN/"

# --- Orca is there under its own name: the link is offered, and made only on a yes ---
MORE=:$HOME/.local/bin
printf '#!/bin/sh\necho "Usage: orca <command>"; echo "  worktree ps   List worktrees"\n' > "$T/keep/orca"; chmod +x "$T/keep/orca"
cp "$T/keep/orca" "$BIN/orca"; ln -s "$(command -v jq)" "$(command -v flock)" "$BIN/"
LINK="ln -s $BIN/orca $HOME/.local/bin/orca-ide"
mv "$BIN/codex" "$T/keep/"
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "Orca without orca-ide: setup stops" 1 $?
check "the link to Orca's own command is offered, as the exact command" "$LINK" "$(printed)"
check "and not made without the flag" 0 "$([ -e "$HOME/.local/bin/orca-ide" ] || [ -L "$HOME/.local/bin/orca-ide" ] && echo 1 || echo 0)"
check "the Codex CLI, for this profile, is the owner's to do" 1 "$(group 'yours to do' | grep -c '^  Codex CLI: .*codex login')"
printf '#!/bin/sh\necho "usage: orca [-h] [-v] screen reader"\n' > "$BIN/orca"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1
check "another program named orca is not linked" '0 0' "$(grep -c 'ln -s' "$T/out") $([ -L "$HOME/.local/bin/orca-ide" ] && echo 1 || echo 0)"
check "and Orca is named as not installed" 1 "$(group 'yours to do' | grep -c 'orca-ide.*Orca .* is not installed')"
cp "$T/keep/orca" "$BIN/orca"
MORE= go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1
check "no folder of the owner's on PATH: said plainly, no link" '1 0' "$(group 'yours to do' | grep -c 'is on PATH and writable') $([ -L "$HOME/.local/bin/orca-ide" ] && echo 1 || echo 0)"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1; check "with the flag and Codex still missing setup stops" 1 $?
check "after making exactly the link it printed" "$BIN/orca" "$(readlink "$HOME/.local/bin/orca-ide")"

# --- a session's PATH is the settings file's env.PATH when that is set, not the shell's ---
# orca-ide is on the shell's PATH (the link just made) and in no folder the settings' PATH names.
cp "$HOME/.claude/settings.json" "$T/keep/settings.json"
jq --arg p "$BIN:$FARM" '.env.PATH = $p' "$T/keep/settings.json" > "$HOME/.claude/settings.json"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1; check "a tool on the shell's PATH alone is missing for the session: setup stops" 1 $?
check "and says so in one plain line" 1 "$(grep -c "^on this shell's PATH but not on the PATH a session gets (env.PATH in .*/.claude/settings.json): Orca's orca-ide command$" "$T/out")"
check "no folder on the session's PATH takes the link: said plainly, nothing offered" '1 0' "$(group 'yours to do' | grep -c 'is on the PATH a session gets and writable') $(grep -c '^  ln -s' "$T/out")"
mkdir "$HOME/bin"; jq --arg p "$BIN:$FARM:$HOME/bin" '.env.PATH = $p' "$T/keep/settings.json" > "$HOME/.claude/settings.json"
SET=$(cat "$HOME/.claude/settings.json")
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "the link is offered in a folder that is on the session's PATH" "ln -s $BIN/orca $HOME/bin/orca-ide" "$(printed)"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1
check "and made there on a yes" "$BIN/orca" "$(readlink "$HOME/bin/orca-ide")"
check "the settings file's PATH is never edited" "$SET" "$(cat "$HOME/.claude/settings.json")"
# Set and empty is still set: a session then finds nothing, whatever the shell has.
jq '.env.PATH = ""' "$T/keep/settings.json" > "$HOME/.claude/settings.json"
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "an empty env.PATH is a session PATH with nothing on it: setup stops" 1 $?
check "and the tools the session lacks are named" 1 "$(grep -c "^on this shell's PATH but not on the PATH a session gets .*: .*jq, git, perl" "$T/out")"
jq '.env = {}' "$T/keep/settings.json" > "$HOME/.claude/settings.json"
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "no env.PATH at all: the shell's PATH alone is checked" 0 "$(grep -c 'PATH a session gets' "$T/out")"
cp "$T/keep/settings.json" "$HOME/.claude/settings.json"; rm -r "$HOME/bin"
rm "$HOME/.local/bin/orca-ide" "$BIN/orca" "$BIN/jq" "$BIN/flock"; MORE=
mv "$T/keep/orca-ide" "$T/keep/codex" "$BIN/"

# --- an install that works: setup carries on, in the same run ---
touch "$T/pm-works"
go setup.sh "${ANSWERS[@]}" --install-missing >"$T/out" 2>&1; check "after an install that supplies everything setup carries on" 0 $?
check "having run the printed command once" "$WANT" "$(cat "$T/pm" 2>/dev/null)"
check "and the project is set up" claude-openai "$(jq -r .profile "$PROJ/.claude/commandeck.json" 2>/dev/null)"
mv "$BIN/gh" "$T/keep/"; printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"
go setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "a gh that is not signed in is the owner's to do" 1 "$(group 'yours to do' | grep -c 'GitHub CLI sign-in: run: gh auth login')"
mv "$T/keep/gh" "$BIN/gh"

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

done_tests

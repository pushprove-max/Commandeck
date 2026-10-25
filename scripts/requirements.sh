#!/usr/bin/env bash
# requirements.sh -- sourced, never run. paths.sh loads it before anything
# else, and setup.sh and doctor.sh before paths.sh. Every line here also runs
# under the Mac's own Bash 3.2, so it keeps to that Bash's syntax. In order:
# the Mac's PATH, the restart under a newer Bash, and the one requirements list
# with its check. One file, so a copy of paths.sh needs only this beside it.

# The scripts use GNU sed -i, stat -c, date -d, readlink -f, grep -P, flock and
# timeout; the Mac's BSD tools break or silently answer differently. Homebrew
# supplies them, in its bin and its gnubin directories.
# A zsh login shell runs path_helper, which puts /usr/bin and /bin ahead of the
# gnubin directories, so those Homebrew directories are moved in front of the
# first system one; entries already ahead (a test stub, nvm) keep their place.
# So no shell start file needs editing for them (a LaunchAgent sets its PATH
# itself). COMMANDECK_BREW_PREFIX relocates Homebrew for the self-test.
# A function, so that setup can call it again after an install made new folders.
# The system is asked once, here: req_check also reads a PATH that may hold no uname.
REQ_UNAME=$(uname -s)
req_path() {
  [ "$REQ_UNAME" = Darwin ] || return 0
  local pp_gnu=() pp_t pp_g pp_path=: pp_added= pp_dirs pp_p pp_pre=(/opt/homebrew /usr/local)
  # Homebrew's folder is the one brew is in: /usr/local on an Intel Mac. Read
  # from brew's own place, not by running `brew --prefix`: this runs at every
  # hook start, and that costs a process each time. A brew linked into a folder
  # that is not Homebrew's (no opt beside it) and no brew at all leave the two
  # known places.
  pp_t=$(command -v brew 2>/dev/null) && [ -d "${pp_t%/bin/brew}/opt" ] && pp_pre=("${pp_t%/bin/brew}")
  [ -z "${COMMANDECK_BREW_PREFIX:-}" ] || pp_pre=("$COMMANDECK_BREW_PREFIX")
  for pp_p in "${pp_pre[@]}"; do
    for pp_t in "$pp_p"/opt/*/libexec/gnubin "$pp_p/bin"; do
      [ -d "$pp_t" ] && pp_gnu+=("$pp_t")
    done
  done
  IFS=: read -ra pp_dirs <<<"$PATH"
  # The trailing newline entry is an end marker: no system directory at all
  # still gets the Homebrew ones, appended.
  for pp_t in "${pp_dirs[@]}" $'\n'; do
    if [ -z "$pp_added" ] && { [ "$pp_t" = /usr/bin ] || [ "$pp_t" = /bin ] || [ "$pp_t" = $'\n' ]; }; then
      pp_added=1
      for pp_g in ${pp_gnu[@]+"${pp_gnu[@]}"}; do
        case $pp_path in *":$pp_g:"*) ;; *) pp_path="$pp_path$pp_g:" ;; esac
      done
    fi
    [ "$pp_t" != $'\n' ] || continue
    case $pp_path in *":$pp_t:"*) ;; *) pp_path="$pp_path$pp_t:" ;; esac
  done
  pp_path=${pp_path#:}; PATH=${pp_path%:}; export PATH
}
req_path

# The system the list is read for. COMMANDECK_HOST_OS is the self-tests' own.
REQ_OS=${COMMANDECK_HOST_OS:-$REQ_UNAME}
REQ_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# req_restart -- a script the Mac's own Bash 3.2 started carries on under
# Homebrew's Bash, with the arguments it was started with and its standard
# input unread. A PATH set here cannot do that: `#!/usr/bin/env bash` has
# already chosen the Bash. Once only: the mark stays set until a Bash 4 or
# newer reads this file, so a "newer" Bash that is not one fails in the check
# below instead of starting again. Never for `bash -c`: there is no file to
# start again.
req_restart() {
  [ "${BASH_VERSINFO[0]}" -lt 4 ] || { unset COMMANDECK_BASH_RESTARTED; return 0; }
  [ "$REQ_OS" = Darwin ] && [ -z "${COMMANDECK_BASH_RESTARTED:-}" ] && [ -z "${BASH_EXECUTION_STRING+x}" ] && [ -f "$0" ] || return 0
  local b i n a=()
  for b in "${COMMANDECK_BREW_PREFIX:-/opt/homebrew}/bin/bash" "${COMMANDECK_BREW_PREFIX:-/usr/local}/bin/bash"; do
    [ -x "$b" ] && "$b" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' </dev/null 2>/dev/null || continue
    # Bash 3 keeps the script's own arguments at the bottom of this stack,
    # whatever was shifted since and whichever function this is read in.
    n=${BASH_ARGC[${#BASH_ARGC[@]}-1]:-0}
    for ((i = 1; i <= n; i++)); do a+=("${BASH_ARGV[${#BASH_ARGV[@]}-i]}"); done
    export COMMANDECK_BASH_RESTARTED=1
    exec "$b" "$0" ${a[@]+"${a[@]}"}
  done
}
req_restart

# req_orca -- print Orca's own command when Orca is on this machine. The Mac
# app ships it as `orca`, not on PATH outside Orca's panes and under no other
# name. Another program is named orca too (a screen reader), so a candidate
# counts only when its help is Orca's.
req_orca() {
  local t c=("$(command -v orca 2>/dev/null)")
  [ "$REQ_OS" != Darwin ] || c+=(/Applications/Orca.app/Contents/Resources/bin/orca "$HOME/Applications/Orca.app/Contents/Resources/bin/orca")
  for t in "${c[@]}"; do
    [ -x "$t" ] && grep -q worktree <<<"$("$t" --help 2>/dev/null </dev/null)" || continue
    printf '%s\n' "$t"; return 0
  done
  return 1
}

# req_bin <PATH> -- print a folder of the owner's that is on that PATH already and can be written.
req_bin() {
  local d
  for d in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin; do
    case ":$1:" in *":$d:"*) [ -d "$d" ] && [ -w "$d" ] && { printf '%s\n' "$d"; return 0; } ;; esac
  done
  return 1
}

# The one list of what the plugin needs on the machine, at the end of
# req_check: setup.sh, doctor.sh and the Mac preflight in paths.sh all read it
# there, and the README's table is written from it. Tab-separated, `-` for none:
#   name   who needs it   check   Homebrew package   apt-get package   the owner's step
# Who: all (every script: the Mac preflight checks these, and setup and doctor
# on any system), mac (the same, on a Mac only), setup (setup and doctor),
# codex (setup and doctor, for the claude-openai profile).
# Check: cmd:<name> is on PATH; gnu:<name> is the GNU one; the rest are named
# in req_check. A row with a package is one the package manager can supply; a
# row with none is the owner's to do, by its step.
# Python: Codex's trust table is read with tomllib (3.11); without it every
# project reads as untrusted and no Codex guard runs.
#
# req_has <check> -- is that row's requirement met on the PATH as it is now.
req_has() {
  case $1 in
    cmd:*) command -v "${1#cmd:}" >/dev/null 2>&1 ;;
    gnu:*) grep -q GNU <<<"$("${1#gnu:}" --version 2>/dev/null)" ;;
    bash4) [ "${BASH_VERSINFO[0]}" -ge 4 ] ;;
    realpath-m) realpath -m /nowhere/x >/dev/null 2>&1 ;;
    tomllib) python3 -c 'import tomllib' 2>/dev/null ;;
    # No gh at all is the row above; this one is a gh that holds no sign-in (asked without the network).
    gh-auth) ! command -v gh >/dev/null 2>&1 || gh auth token >/dev/null 2>&1 ;;
    orca) command -v orca-ide >/dev/null 2>&1 ;;
    *) false ;;
  esac
}

# req_check <all|setup> [profile] -- 0 when nothing in the list is missing for
# that caller. Else: REQ_NAMES is what can be installed, REQ_CMD the one
# package manager command for it, REQ_LINK the command that links orca-ide to
# Orca's own command, REQ_YOURS one line per thing only the owner can do, and
# REQ_NOTES one line per PATH that lacks what the other has.
# Two PATHs are checked. The user settings file can carry its own env.PATH,
# which replaces the shell's inside every session, hooks included; a tool on
# one and not the other is missing for one of the two, and no package supplies
# it. The settings file is read, never written.
req_check() {
  local who=$1 profile=${2:-} name need check brew apt step pkg pkgs= names= t d a b sp has= on1= on2= where=PATH
  REQ_NAMES= REQ_CMD=() REQ_LINK=() REQ_YOURS=() REQ_NOTES=()
  # Set and empty is still set: has, not the text, says whether there is one.
  # A script in a session gets the same Mac fix as here, so the session's PATH is read with it.
  if sp=$(jq -er '.env.PATH | strings' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null); then
    has=1 where="the PATH a session gets"; sp=$(PATH=$sp; req_path; printf '%s' "$PATH")
  fi
  while IFS=$'\t' read -r name need check brew apt step; do
    case $name in ''|'#'*) continue ;; esac
    case $need in
      all) ;;
      mac) [ "$REQ_OS" = Darwin ] || continue ;;
      setup) [ "$who" = setup ] || continue ;;
      codex) [ "$who" = setup ] && [ "$profile" = claude-openai ] || continue ;;
      *) continue ;;
    esac
    a=0 b=0; req_has "$check" || a=1
    if [ -n "$has" ] && [ "$sp" != "$PATH" ]; then (PATH=$sp; req_has "$check") || b=1; else b=$a; fi
    [ "$a$b" != 00 ] || continue
    [ "$a$b" != 01 ] || on1="$on1, $name"
    [ "$a$b" != 10 ] || on2="$on2, $name"
    # On one PATH only: it is installed, so no package is named for it. The
    # link is still offered when it is the session that lacks orca-ide.
    [ "$a$b" = 11 ] || [ "$check$a$b" = orca01 ] || continue
    if [ "$check" = orca ]; then
      if t=$(req_orca); then
        if d=$([ -n "$has" ] || sp=$PATH; req_bin "$sp"); then REQ_LINK=(ln -s "$t" "$d/orca-ide"); REQ_NAMES=$name
        else REQ_YOURS+=("$name: Orca is installed and its command is $t, but none of $HOME/.local/bin, $HOME/bin and /usr/local/bin is on $where and writable. Link it into a folder on $where yourself, for one: sudo ln -s $(printf '%q' "$t") /usr/local/bin/orca-ide"); fi
        continue
      fi
      t="the orca-ide .deb, .rpm or AppImage"; [ "$REQ_OS" != Darwin ] || t="the Mac .dmg for this chip ($(uname -m))"
      step=${step/\%s/$t}
    fi
    pkg=$apt; [ "$REQ_OS" != Darwin ] || pkg=$brew
    if [ "$pkg" = - ]; then REQ_YOURS+=("$name: $step"); continue; fi
    names="$names, $name"
    case " $pkgs " in *" $pkg "*) ;; *) pkgs="$pkgs $pkg" ;; esac
  done <<'LIST'
Bash 4 or newer	all	bash4	bash	bash	-
GNU sed	all	gnu:sed	gnu-sed	sed	-
GNU stat	all	gnu:stat	coreutils	coreutils	-
GNU date	all	gnu:date	coreutils	coreutils	-
GNU readlink	all	gnu:readlink	coreutils	coreutils	-
GNU grep	all	gnu:grep	grep	grep	-
gsed	mac	cmd:gsed	gnu-sed	-	-
gstat	mac	cmd:gstat	coreutils	-	-
gdate	mac	cmd:gdate	coreutils	-	-
greadlink	mac	cmd:greadlink	coreutils	-	-
ggrep	mac	cmd:ggrep	grep	-	-
flock	all	cmd:flock	flock	util-linux	-
timeout	all	cmd:timeout	coreutils	coreutils	-
GNU realpath	setup	realpath-m	coreutils	coreutils	-
sha1sum	setup	cmd:sha1sum	coreutils	coreutils	-
sha256sum	setup	cmd:sha256sum	coreutils	coreutils	-
jq	setup	cmd:jq	jq	jq	-
git	setup	cmd:git	git	git	-
perl	setup	cmd:perl	perl	perl	-
ripgrep (rg)	setup	cmd:rg	ripgrep	ripgrep	-
Python 3.11 or newer	setup	tomllib	python3	python3	-
GitHub CLI (gh)	setup	cmd:gh	gh	gh	-
GitHub CLI sign-in	setup	gh-auth	-	-	run: gh auth login
Orca's orca-ide command	setup	orca	-	-	Orca (https://github.com/stablyai/orca) is not installed, and orca-ide is its command. Download %s from https://github.com/stablyai/orca/releases, install it, then run setup again
Codex CLI	codex	cmd:codex	-	-	install the Codex CLI (https://github.com/openai/codex), then run: codex login
LIST
  if [ -n "$pkgs" ]; then
    # $pkgs is split on purpose: one word per package.
    if [ "$REQ_OS" = Darwin ]; then
      if command -v brew >/dev/null 2>&1; then REQ_CMD=(brew install $pkgs)
      else REQ_YOURS+=("Homebrew: it is not installed, and it supplies ${names#, }. Install it from https://brew.sh, then run setup again"); names=; fi
    elif command -v apt-get >/dev/null 2>&1; then REQ_CMD=(sudo apt-get install -y $pkgs)
    else REQ_YOURS+=("${names#, }: there is no apt-get on this machine. Install them with its own package manager, then run setup again"); names=; fi
  fi
  REQ_NAMES=${names#, }${REQ_NAMES:+${names:+, }$REQ_NAMES}
  t="the PATH a session gets (env.PATH in ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json)"
  [ -z "$on1" ] || REQ_NOTES+=("on this shell's PATH but not on $t: ${on1#, }")
  [ -z "$on2" ] || REQ_NOTES+=("on $t but not on this shell's PATH: ${on2#, }")
  [ -z "$REQ_NAMES" ] && [ ${#REQ_YOURS[@]} = 0 ] && [ ${#REQ_NOTES[@]} = 0 ]
}

# req_report -- the last check's two groups, as setup, doctor and the Mac preflight all print them.
req_report() {
  local l
  if [ -n "$REQ_NAMES" ]; then
    echo "can install: $REQ_NAMES. setup.sh --install-missing runs exactly:"
    [ ${#REQ_CMD[@]} = 0 ] || echo "  ${REQ_CMD[*]}"
    [ ${#REQ_LINK[@]} = 0 ] || { l=$(printf '%q ' "${REQ_LINK[@]}"); echo "  ${l% }"; }
  fi
  [ ${#REQ_YOURS[@]} = 0 ] || { echo "yours to do:"; printf '  %s\n' "${REQ_YOURS[@]}"; }
  [ ${#REQ_NOTES[@]} = 0 ] || printf '%s\n' "${REQ_NOTES[@]}"
}

# req_install -- run what the last check named, the same words it printed. A
# command that fails is not an error here: the caller checks again.
req_install() {
  [ ${#REQ_CMD[@]} = 0 ] || "${REQ_CMD[@]}" || true
  [ ${#REQ_LINK[@]} = 0 ] || "${REQ_LINK[@]}" || true
}

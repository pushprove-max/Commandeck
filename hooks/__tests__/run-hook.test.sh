#!/usr/bin/env bash
# run-hook.test.sh -- on a Mac the first bash on PATH can be the system's 3.2.
# Seven hooks do not parse under it, hooks.json started each hook by its own
# path, and a hook that fails blocks the command it guards: every Bash call and
# every Read in the session was refused. What this pins: every hook is started
# through hooks/lib/run-hook.sh; with no Bash 4 or newer to be found each one
# exits 0 with one plain line and blocks nothing; with one found the hook runs
# under it with its arguments and gets its payload byte for byte; and the
# launcher itself is plain sh, so the old Bash can read it.
# The "old" bash is the machine's own /bin/bash where that is 3.x (a Mac), and
# a stand-in that fails where it is not.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
RUN=$ROOT/hooks/lib/run-hook.sh
NEW=$BASH
mkdir -p "$T/old" "$T/none" "$T/brew/bin" "$T/real/bin" "$T/home" "$T/proj"
if [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" -lt 4 ]; then ln -s /bin/bash "$T/old/bash"
else printf '#!/bin/sh\nexit 1\n' > "$T/old/bash"; chmod +x "$T/old/bash"; fi
# A payload no line-based copy survives: an empty line, a NUL byte, no final newline.
printf '{"tool_name":"Bash"}\n\n\000tail' > "$T/payload"
# started <homebrew folder> <command> -- the command as Claude Code starts it, old bash first on PATH.
started() { env PATH="$T/old:$PATH" HOME="$T/home" CLAUDE_PROJECT_DIR="$T/proj" COMMANDECK_BREW_PREFIX="$1" CLAUDE_PLUGIN_ROOT="$ROOT" sh -c "$2" < "$T/payload"; }
mapfile -t CMDS < <(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json")
check "hooks.json registers hooks" 1 "$([ "${#CMDS[@]}" -ge 40 ] && echo 1 || echo 0)"
check "every hook in hooks.json is started through the launcher" 0 \
  "$(printf '%s\n' "${CMDS[@]}" | grep -vc '^"${CLAUDE_PLUGIN_ROOT}/hooks/lib/run-hook.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/[a-z-]*\.sh"\( --[a-z-]*\)\{0,1\}$')"
check "and so is every hook worktree setup registers" 0 "$(grep -c '"\\"$HOOKS/[a-z-]*\.sh\\""' "$ROOT/scripts/worktree-setup.sh")"
check "the launcher is plain sh" 0 "$(/bin/sh -n "$RUN" 2>&1 | grep -c .)"

# --- no Bash 4 or newer: one line, exit 0, nothing blocked ---
BAD=0 LINES=0
for c in "${CMDS[@]}"; do
  OUT=$(started "$T/none" "$c" 2>&1); [ $? = 0 ] || BAD=$((BAD + 1))
  [ "$(grep -c 'commandeck: no Bash 4 or newer' <<<"$OUT")" = 1 ] && [ "$(wc -l <<<"$OUT" | tr -d ' ')" = 1 ] || LINES=$((LINES + 1))
done
check "with no Bash 4 or newer no hook exits non-zero" 0 "$BAD"
check "and each prints the one line and nothing else" 0 "$LINES"
check "the line says setup can install it" 1 "$(started "$T/none" "${CMDS[0]}" 2>&1 | grep -c 'setup can install')"

# --- a newer Bash in Homebrew's place: the hook is run under it, payload untouched ---
# The stand-in answers the launcher's version question as the real one and records every hook it is given.
printf '#!/bin/sh\ncase $1 in -c) exec %q "$@" ;; esac\necho "$*" >> %q; cat > %q\n' "$NEW" "$T/started" "$T/got" > "$T/brew/bin/bash"
chmod +x "$T/brew/bin/bash"
BAD=0
for c in "${CMDS[@]}"; do
  rm -f "$T/got"; started "$T/brew" "$c" >/dev/null 2>&1
  cmp -s "$T/payload" "$T/got" || BAD=$((BAD + 1))
done
check "each hook's payload reaches the newer Bash byte for byte" 0 "$BAD"
check "each hook is handed over with its own arguments, once" "$(printf '%s\n' "${CMDS[@]}" | sed "s|\"\${CLAUDE_PLUGIN_ROOT}/hooks/lib/run-hook.sh\" ||; s|\${CLAUDE_PLUGIN_ROOT}|$ROOT|g" | tr -d '"')" "$(cat "$T/started" 2>/dev/null)"

# --- and a real one: the hook body runs under Bash 4 or newer ---
ln -s "$NEW" "$T/real/bin/bash"
printf 'echo "${BASH_VERSINFO[0]} $* $(cksum)"\n' > "$T/probe.sh"
check "a hook runs under the newer Bash with its arguments and its payload" "${BASH_VERSINFO[0]} --stop $(cksum < "$T/payload")" \
  "$(started "$T/real" "\"$RUN\" \"$T/probe.sh\" --stop" 2>&1)"
check "with no Homebrew the newer Bash on PATH is used" "${BASH_VERSINFO[0]}  $(cksum < "$T/payload")" \
  "$(env PATH="$T/real/bin:$PATH" COMMANDECK_BREW_PREFIX="$T/none" sh -c "\"$RUN\" \"$T/probe.sh\"" < "$T/payload" 2>&1)"

# --- on a Mac a hook gets the PATH the scripts give themselves ---
# A session's PATH has /usr/bin ahead of Homebrew's GNU folders, or not them at
# all. The hooks use GNU date, sed and stat; with the Mac's own they wrote empty
# timestamps and said nothing.
if [ "$(uname -s)" = Darwin ]; then
  mkdir -p "$T/real/opt/coreutils/libexec/gnubin" "$T/mine"
  printf 'echo "$PATH"\n' > "$T/path.sh"
  check "a hook finds Homebrew's GNU tools ahead of the system's, and the owner's folders still first" "$T/mine:$T/real/opt/coreutils/libexec/gnubin:$T/real/bin:/usr/bin:/bin" \
    "$(env PATH="$T/mine:/usr/bin:/bin:$T/real/bin" COMMANDECK_BREW_PREFIX="$T/real" sh -c "\"$RUN\" \"$T/path.sh\"" < "$T/payload" 2>&1)"
  # An Intel Mac keeps Homebrew under /usr/local, not /opt/homebrew: the folder is the one `brew` is in,
  # wherever that is. With only /opt/homebrew read, the hooks there kept the Mac's own tools.
  mkdir -p "$T/intel/bin" "$T/intel/opt/coreutils/libexec/gnubin"
  printf '#!/bin/sh\necho "brew was run" >> %q\n' "$T/brew-ran" > "$T/intel/bin/brew"; chmod +x "$T/intel/bin/brew"
  check "Homebrew under another prefix (an Intel Mac's) is found by where brew is" "$T/mine:$T/intel/opt/coreutils/libexec/gnubin:$T/intel/bin:/usr/bin:/bin" \
    "$(env -u COMMANDECK_BREW_PREFIX PATH="$T/mine:/usr/bin:/bin:$T/intel/bin" sh -c "\"$RUN\" \"$T/path.sh\"" < "$T/payload" 2>&1)"
  check "and no brew process is started for it, on every hook" no "$([ -e "$T/brew-ran" ] && echo yes || echo no)"
  # No brew on PATH at all: both known places are read, so whichever this Mac has leads.
  KNOWN=$(for d in /opt/homebrew/bin /usr/local/bin; do [ ! -d "$d" ] || printf '%s:' "$d"; done)
  check "with no brew on PATH both known Homebrew places are read" "$KNOWN/usr/bin:/bin" \
    "$(env -u COMMANDECK_BREW_PREFIX PATH="/usr/bin:/bin" sh -c "\"$RUN\" \"$T/path.sh\"" < "$T/payload" 2>&1 | tr ':' '\n' | grep -v '/libexec/gnubin$' | paste -sd: -)"
else echo "NOT RUN here (not a Mac): a hook finds Homebrew's GNU tools ahead of the system's"; fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

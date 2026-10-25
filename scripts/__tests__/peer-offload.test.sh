#!/usr/bin/env bash
# covers: scripts/peer-offload.sh scripts/run-shell-tests.sh scripts/host-services.sh
# A Mac linked worktree whose chain host is the PC runs its shell tests on the PC (owner ruling 2026-10-25): the Mac
# runs out of memory under parallel Builders' suites. Pinned: the files run there against the worktree's exact tree,
# uncommitted work included, and their result comes back; a red run there is not run again here; the main checkout,
# a Mac whose chain host is the Mac, and the run on the PC itself never hand off; an unreachable PC runs the files
# here once; a PC that refuses fails the run with nothing run here; a run that started there and lost its connection
# fails with nothing run here; a file marked `# host: mac` stays here.
# The PC is this machine under its own HOME, reached through a stub ssh.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@t "$@"; }

# The project: the real scripts, and three test files that log where they ran to $T/where.
git init -q --bare -b main "$T/origin.git"
git init -q -b main "$T/mac"; mkdir -p "$T/mac/scripts/__tests__"
cp "$REAL"/scripts/*.sh "$T/mac/scripts/"
printf '#!/usr/bin/env bash\necho "where $PWD" >> %q\n' "$T/where" > "$T/mac/scripts/__tests__/where.test.sh"
printf '#!/usr/bin/env bash\necho "red $PWD" >> %q\nexit 1\n' "$T/where" > "$T/mac/scripts/__tests__/red.test.sh"
printf '#!/usr/bin/env bash\n# host: mac\necho "mac $PWD" >> %q\n' "$T/where" > "$T/mac/scripts/__tests__/mac.test.sh"
g -C "$T/mac" add -A && g -C "$T/mac" commit -qm first
git -C "$T/mac" remote add origin "$T/origin.git" && git -C "$T/mac" push -q origin main && git -C "$T/mac" fetch -q origin
git -C "$T/mac" worktree add -q -b b "$T/wt"
# A commit the PC lacks (it travels as a bundle) and an uncommitted edit (it travels as a patch).
printf 'echo committed >> %q\n' "$T/where" >> "$T/wt/scripts/__tests__/where.test.sh"; g -C "$T/wt" commit -qam second
printf 'echo uncommitted >> %q\n' "$T/where" >> "$T/wt/scripts/__tests__/where.test.sh"

# The Mac's devenv: the peer is "pc", and the chain host is pc. The PC's HOME has the same, so a hand-off from the PC
# would be seen as a second ssh call.
for h in mac-home pc-home; do mkdir -p "$T/$h/.config/devenv"; echo pc > "$T/$h/.config/devenv/peer"; echo pc > "$T/$h/.config/devenv/chain-host"; done
# ssh: each call is a line in $T/ssh-calls; $T/down makes it fail as an unreachable host does (255, nothing in its -E
# log). Otherwise it logs `Authenticated to pc` to its -E file, as ssh does once a session is established, and runs the
# remote command here under the PC's HOME, with a systemd-run that only runs its command.
mkdir -p "$T/bin" "$T/pcbin"
cat > "$T/bin/ssh" <<EOF
#!/usr/bin/env bash
echo call >> "$T/ssh-calls"
E=/dev/null p=
for a; do [ "\$p" != -E ] || E=\$a; p=\$a; done
[ ! -e "$T/down" ] || { echo "ssh: connect to host pc port 22: Connection refused" >> "\$E"; exit 255; }
echo 'Authenticated to pc ([192.0.2.1]:22) using "publickey".' >> "\$E"
# \$T/drop holds "<code> <lost>": the session opened, then ended with <code>, losing <lost>: exit (the exit line),
# lines (every control line of the run), all (the connection drops before the command runs).
if [ -e "$T/drop" ]; then
  read -r code lost < "$T/drop"
  case \$lost in
    exit) del='/^offload-exit: /d;/^offload-done: /d' ;;
    lines) del='/^offload-/d;/^offload: /d' ;;
    all) exit "\$code" ;;
  esac
  (cd "$T/pc-home" && env -u COMMANDECK_HOST_OS HOME="$T/pc-home" PATH="$T/pcbin:$T/bin:\$PATH" bash -c "\$a") | sed "\$del"
  exit "\$code"
fi
cd "$T/pc-home" && exec env -u COMMANDECK_HOST_OS HOME="$T/pc-home" PATH="$T/pcbin:$T/bin:\$PATH" bash -c "\$a"
EOF
cat > "$T/pcbin/systemd-run" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do case $1 in -p) shift 2 ;; -*) shift ;; *) break ;; esac; done
exec "$@"
EOF
chmod +x "$T/bin/ssh" "$T/pcbin/systemd-run"
# run <checkout> <file>... -- the runner there, as a Mac session runs it (outside any test run).
run() { local co=$1; shift; : > "$T/where"; : > "$T/ssh-calls"
  (cd "$co" && env -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_OFFLOADED HOME="$T/mac-home" COMMANDECK_HOST_OS=Darwin COMMANDECK_FOREGROUND=1 \
    PATH="$T/bin:$PATH" bash scripts/run-shell-tests.sh "$@" 2>&1); }
calls() { wc -l < "$T/ssh-calls" | tr -d ' '; }
# here <kind> -- how many lines of <kind> ran in the Mac's worktree; there <kind> -- in a copy on the PC.
here() { grep -c "^$1 $T/wt\$" "$T/where"; }
there() { grep -c "^$1 $T/pc-home/" "$T/where"; }

OUT=$(run "$T/wt" scripts/__tests__/where.test.sh scripts/__tests__/mac.test.sh); RC=$?
check "a Mac linked worktree with chain host pc: the files run on the PC against the uncommitted tree, exit passed back" \
  "0 1 1 0 1 1" "$RC $(grep -c '^offload: started on pc tree ' <<<"$OUT") $(there where) $(here where) $(grep -cx committed "$T/where") $(grep -cx uncommitted "$T/where")"
check "a file marked host: mac runs here, the rest there" "1 0" "$(here mac) $(there mac)"
check "the run on the PC does not hand off again" 1 "$(calls)"
# Only a whole `# host: mac` keeps a file here: one that merely starts with mac goes to the PC with the rest.
printf '#!/usr/bin/env bash\n# host: machine\necho "machine $PWD" >> %q\n' "$T/where" > "$T/wt/scripts/__tests__/machine.test.sh"
OUT=$(run "$T/wt" scripts/__tests__/machine.test.sh); RC=$?
check "a marker that only starts with mac (# host: machine) does not keep a file here" "0 1 0" "$RC $(there machine) $(here machine)"
rm -f "$T/wt/scripts/__tests__/machine.test.sh"

OUT=$(run "$T/wt" scripts/__tests__/red.test.sh); RC=$?
check "a red run on the PC is the result: exit 1, and it is not run again here" "1 1 0 1" \
  "$RC $(there red) $(here red) $(grep -c '^offload: exit 1' <<<"$OUT")"

OUT=$(run "$T/mac" scripts/__tests__/where.test.sh); RC=$?
check "the main checkout never hands off: the files run here, no ssh" "0 1 0" "$RC $(grep -c "^where $T/mac\$" "$T/where") $(calls)"

echo mac > "$T/mac-home/.config/devenv/chain-host"
OUT=$(run "$T/wt" scripts/__tests__/where.test.sh); RC=$?
check "a Mac whose chain host is the Mac runs the files here, no ssh" "0 1 0" "$RC $(here where) $(calls)"
echo pc > "$T/mac-home/.config/devenv/chain-host"

touch "$T/down"
OUT=$(run "$T/wt" scripts/__tests__/where.test.sh); RC=$?
check "an unreachable PC: the files run here once, and the reason is said" "0 1 0 1 1" \
  "$RC $(here where) $(there where) $(grep -c 'unreachable or asleep' <<<"$OUT") $(grep -c 'running here, once' <<<"$OUT")"
rm -f "$T/down"

# Every ordering found so far (Decision G13-3), in order: the exit line lost after the start (r4: 255, then 2); the
# start and exit lines lost (r5, r7: 255, then 2); a drop after the session opened, before anything ran (r7: 255).
# What came back over ssh never proves what the PC did, so each one fails and nothing runs here, whatever piece of the
# stream was removed between two runs. Then the PC never connects (asleep): the one way the files run here, once.
for step in "255 exit 1" "2 exit 1" "255 lines 1" "2 lines 1" "255 all 0"; do
  set -- $step; echo "$1 $2" > "$T/drop"
  OUT=$(run "$T/wt" scripts/__tests__/where.test.sh); RC=$?
  check "every ordering found so far: an opened session ends $1 with $2 lost: it fails, nothing runs here, the PC may still be running it" \
    "1 $3 0 1 0" "$RC $(there where) $(here where) $(grep -c 'the PC may still be running it' <<<"$OUT") $(grep -c 'running here, once\|refused the run' <<<"$OUT")"
done
rm -f "$T/drop"; touch "$T/down"
OUT=$(run "$T/wt" scripts/__tests__/where.test.sh); RC=$?
check "every ordering found so far: a PC that never connects (asleep): the files run here once" "0 1 0 1" \
  "$RC $(here where) $(there where) $(grep -c 'running here, once' <<<"$OUT")"
rm -f "$T/down"

# The PC cannot create its repository: a file where its folder goes.
rm -rf "$T/pc-home/.cache"; mkdir -p "$T/pc-home"; : > "$T/pc-home/.cache"
OUT=$(run "$T/wt" scripts/__tests__/where.test.sh); RC=$?
check "the PC refuses (it cannot set up its copy): exit 2, and nothing runs here or there" "2 0 0 1" \
  "$RC $(here where) $(there where) $(grep -c 'the hand-off to the PC was refused or failed (reason above); nothing ran here' <<<"$OUT")"
# The same refusal with its refusal line lost on the way: it cannot be told from a run that started, so it fails
# (exit 1), nothing runs here.
echo "2 lines" > "$T/drop"
OUT=$(run "$T/wt" scripts/__tests__/where.test.sh); RC=$?
check "a refusal whose refusal line is lost: exit 1, nothing runs here" "1 0 0 1" \
  "$RC $(here where) $(there where) $(grep -c 'the PC may still be running it' <<<"$OUT")"
rm -f "$T/drop" "$T/pc-home/.cache"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

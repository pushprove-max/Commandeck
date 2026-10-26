#!/usr/bin/env bash
# post-fix-checks.test.sh -- what it pins: the post-fix checks start together, the round waits for all of them, and
# each result is reported under its own name, so a red check is never hidden behind a later green one. The runner is
# copied into a scratch plugin checkout with a stub run-shell-tests.sh, a stub paths.sh and a `claude` stub on PATH,
# so no real suite or mod test runs.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)/post-fix-checks.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

# Run directly, this is the outer run. Two bystanders stand in for another run's sleeps on a shared host; the body
# runs as a child, and the bystanders are checked only after it has exited, so the check reads the EXIT cleanup that
# really ran. The body's own sleeps are `sleep 60.<tag>`, the tag being the outer's bare pid, unique while it lives.
if [ -z "${PFC_TAG:-}" ]; then
  sleep 60.9 & B1=$!
  sleep "60.${$}1" & B2=$!
  trap 'kill "$B1" "$B2" 2>/dev/null' EXIT
  BODY=$(PFC_TAG=$$ bash "$0" 2>&1)
  if [[ $(tail -n 1 <<<"$BODY") =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]]; then
    PASS=${BASH_REMATCH[1]} FAIL=${BASH_REMATCH[2]}; sed '$d' <<<"$BODY"
  else
    echo "$BODY"; echo "FAIL the body ended without its count line"; PASS=0 FAIL=1
  fi
  check "another run's sleeps survive this run's checks and cleanup" yes \
    "$({ kill -0 "$B1" && kill -0 "$B2"; } 2>/dev/null && echo yes || echo no)"
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]; exit
fi

TMP=$(mktemp -d)
SLEEP_DUR="60.$PFC_TAG"
MINE="sleep 60\\.$PFC_TAG\$"
trap 'pkill -f "$MINE" 2>/dev/null; rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/scripts" "$REPO/.claude-plugin" "$TMP/bin" "$TMP/stub"
git -C "$REPO" init -q
echo '{"name": "p", "version": "1.0.0"}' > "$REPO/.claude-plugin/plugin.json"
cp "$SRC" "$REPO/scripts/post-fix-checks.sh"
echo 'PP_SCRATCH=${COMMANDECK_SCRATCH:?}' > "$REPO/scripts/paths.sh"

# One stub body for every check. STUB_RC_<name> is its exit code, STUB_SLEEP_<name> a sleep before it, and
# STUB_WAIT_ALL=1 makes it exit 97 unless all three stubs have started within 10 s, so a runner that waits between
# starts fails with no timing race.
cat > "$TMP/stub/check.sh" <<'STUB'
#!/usr/bin/env bash
name=$1; shift
echo "$*" >> "$STUBDIR/$name.args"
: > "$STUBDIR/$name.started"
all() { [ -e "$STUBDIR/shell.started" ] && [ -e "$STUBDIR/validate.started" ] && [ -e "$STUBDIR/mods.started" ]; }
if [ "${STUB_WAIT_ALL:-}" = 1 ]; then
  for _ in $(seq 1 100); do all && break; sleep 0.1; done
  all || exit 97
fi
eval "s=\${STUB_SLEEP_$name:-}"; [ -n "$s" ] && sleep "$s"
echo "marker-$name"
eval "exit \${STUB_RC_$name:-0}"
STUB
cat > "$REPO/scripts/run-shell-tests.sh" <<STUB
#!/usr/bin/env bash
exec bash "$TMP/stub/check.sh" shell "\$@"
STUB
cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in "plugin validate") n=validate ;; "plugin test") n=mods ;; *) exit 64 ;; esac
exec bash "$TMP/stub/check.sh" "\$n" "\$@"
STUB
chmod +x "$REPO/scripts/run-shell-tests.sh" "$TMP/bin/claude"

# run_runner <case dir name> [VAR=value ...] -- sets OUT (stdout and stderr) and RC.
run_runner() {
  local d=$1; shift
  export STUBDIR="$TMP/$d.stubs" COMMANDECK_SCRATCH="$TMP/$d.scratch"
  rm -rf "$STUBDIR" "$COMMANDECK_SCRATCH"; mkdir -p "$STUBDIR"
  OUT=$(cd "$REPO" && env PATH="$TMP/bin:$PATH" "$@" bash scripts/post-fix-checks.sh a.test.sh 'b c.test.sh' 2>&1); RC=$?
}

run_runner once STUB_WAIT_ALL=1
check "runs every check at once: exit 0 and the green line" "0 yes" "$RC $(has "$OUT" 'post-fix: all green')"
check "runs every check at once: each saw its own command" "a.test.sh b c.test.sh|plugin validate .|plugin test ." \
  "$(cat "$STUBDIR/shell.args")|$(cat "$STUBDIR/validate.args")|$(cat "$STUBDIR/mods.args")"

run_runner two STUB_RC_validate=2 STUB_RC_mods=3
check "two failures keep their own codes: exit 1, one line each, the summary" "1 yes yes yes yes" \
  "$RC $(has "$OUT" 'post-fix: shell exit 0') $(has "$OUT" 'post-fix: validate exit 2') $(has "$OUT" 'post-fix: mods exit 3') $(has "$OUT" 'post-fix: 2 of 3 failed: validate,mods')"
check "two failures keep their own codes: every log kept, both red tails printed" "mods.log shell.log validate.log |yes yes" \
  "$(ls "$COMMANDECK_SCRATCH"/post-fix.*/ 2>/dev/null | tr '\n' ' ')|$(has "$OUT" marker-validate) $(has "$OUT" marker-mods)"

run_runner early STUB_RC_shell=2 STUB_SLEEP_validate=1 STUB_SLEEP_mods=1
check "an early failure survives later successes" "1 yes yes no" \
  "$RC $(has "$OUT" 'post-fix: shell exit 2') $(has "$OUT" 'post-fix: 1 of 3 failed: shell') $(has "$OUT" 'all green')"

T0=$SECONDS
run_runner hung STUB_SLEEP_mods=$SLEEP_DUR POST_FIX_CHECK_TIMEOUT_S=2
check "a hung check is cut off at the cap and named" "1 yes yes yes yes" \
  "$RC $([ $((SECONDS - T0)) -lt 20 ] && echo yes) $(has "$OUT" 'mods timed out after 2s') $(has "$OUT" 'post-fix: shell exit 0') $(has "$OUT" 'post-fix: validate exit 0')"

export STUBDIR="$TMP/killed.stubs" COMMANDECK_SCRATCH="$TMP/killed.scratch"
rm -rf "$STUBDIR" "$COMMANDECK_SCRATCH"; mkdir -p "$STUBDIR"
(cd "$REPO" && exec env PATH="$TMP/bin:$PATH" STUB_SLEEP_shell=$SLEEP_DUR STUB_SLEEP_validate=$SLEEP_DUR STUB_SLEEP_mods=$SLEEP_DUR \
  bash scripts/post-fix-checks.sh a.test.sh) > "$TMP/killed.out" 2>&1 &
RUNNER=$!
for _ in $(seq 1 100); do [ -e "$STUBDIR/shell.started" ] && [ -e "$STUBDIR/validate.started" ] && [ -e "$STUBDIR/mods.started" ] && break; sleep 0.1; done
kill -TERM "$RUNNER"; wait "$RUNNER"; KRC=$?
for _ in $(seq 1 150); do pgrep -f "$MINE" >/dev/null || break; sleep 0.1; done
check "a killed run leaves no check running: none alive, non-zero, logs kept, no green line, each named" "no yes yes no yes" \
  "$(pgrep -f "$MINE" >/dev/null && echo yes || echo no) $([ "$KRC" -ne 0 ] && echo yes) $(ls -d "$COMMANDECK_SCRATCH"/post-fix.* >/dev/null 2>&1 && echo yes || echo no) $(has "$(cat "$TMP/killed.out")" 'all green') $(has "$(cat "$TMP/killed.out")" 'interrupted: shell cut off')"

rm "$REPO/.claude-plugin/plugin.json"
OUT=$(cd "$REPO" && COMMANDECK_SCRATCH="$TMP/none.scratch" bash scripts/post-fix-checks.sh 2>&1); RC=$?
check "a checkout with nothing to check exits 2" "2 yes no" "$RC $(has "$OUT" 'nothing to check') $([ -d "$TMP/none.scratch" ] && echo yes || echo no)"

HELP=$(bash "$SRC" --help 2>&1); HRC=$?
check "--help prints usage and an example, exit 0" "0 yes yes" "$HRC $(has "$HELP" 'usage: post-fix-checks.sh') $(has "$HELP" 'example:')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

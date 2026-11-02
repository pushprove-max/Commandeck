#!/usr/bin/env bash
# covers: scripts/main-watch.sh
# Issue 537: on macOS a service started with MallocStackLogging set writes a stack-logs file per child shell, and one
# filled a disk. main-watch drops the two variables once, so every child shell it starts (ps, orca-ide, jq) runs
# without allocator logging; and its own log, which launchd holds open, stays under 1 MiB however many ticks run.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
tick 5000

# Every child the watcher starts reads its own environment: the stand-ins log what they were given.
printf '#!/usr/bin/env bash\necho "ps:${MallocStackLogging-unset}:${MallocStackLoggingNoCompact-unset}" >> %q\ncase "$*" in *lstart=*) exec /bin/ps "$@" ;; esac\nexit 0\n' "$T/env-seen" > "$T/bin/ps"
mv "$T/bin/orca-ide" "$T/bin/orca-ide.real"
printf '#!/usr/bin/env bash\necho "orca:${MallocStackLogging-unset}:${MallocStackLoggingNoCompact-unset}" >> %q\nexec %q "$@"\n' "$T/env-seen" "$T/bin/orca-ide.real" > "$T/bin/orca-ide"
chmod +x "$T/bin/ps" "$T/bin/orca-ide"
: > "$T/env-seen"
export MallocStackLogging=1 MallocStackLoggingNoCompact=1
tick 5060
unset MallocStackLogging MallocStackLoggingNoCompact
[ -s "$T/env-seen" ] || fail "no child shell ran, so the case proves nothing"
bad=$(grep -v ':unset:unset$' "$T/env-seen" | sort -u | head -3 | tr '\n' ' ' || true)
[ -z "$bad" ] || fail "main-watch's child shells still see allocator logging: $bad"

# A log already past the cap is cut at the first tick and stays under it as ticks go on.
LOG=$S/scratchpad/main-watch.log
mkdir -p "$S/scratchpad"
head -c 3000000 /dev/zero | tr '\0' 'x' > "$LOG"
for i in 1 2 3 4 5; do
  tick $((6000 + i * 60))
  head -c 300000 /dev/zero | tr '\0' 'y' >> "$LOG"
done
tick 7000
[ "$(wc -c < "$LOG")" -le 1048576 ] || fail "a log past the cap is $(wc -c < "$LOG") bytes after many ticks, over the 1 MiB cap"

echo "PASS main-watch-malloc.test.sh"

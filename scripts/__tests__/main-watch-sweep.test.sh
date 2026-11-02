#!/usr/bin/env bash
# Issue 577: each tick sends TERM to the pids `codex-helpers.sh orphans` lists (brokers and TypeScript language servers
# whose folder is gone), and to nothing when the list is empty. codex-helpers.sh is a stub here, and kill a PATH stub
# that records its calls (main-watch kills through `env kill`, as reap_brokers does), so no real process is touched.
# Each check prints `ok <label>` or `FAIL <label> (why)` and the run goes on, so one break names its own check.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
RC=0
verdict() { if [ -z "$2" ]; then echo "ok $1"; else echo "FAIL $1 ($2)" >&2; RC=1; fi; }
cat > "$REPO/scripts/codex-helpers.sh" <<EOS
#!/usr/bin/env bash
[ "\$1" != orphans ] || cat "$F/orphans" 2>/dev/null || true
EOS
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$F/kills" > "$T/bin/kill"; chmod +x "$T/bin/kill"
: > "$F/kills"

printf '%s\n' "4242 4243" > "$F/orphans"; tick 5000
r=; [ "$(sort "$F/kills" | tr '\n' ' ')" = "-TERM 4242 -TERM 4243 " ] || r="stopped: [$(cat "$F/kills")]"
verdict "a tick stops what the orphan list names" "$r"

: > "$F/kills"; : > "$F/orphans"; tick 5060
r=; [ ! -s "$F/kills" ] || r="stopped: [$(cat "$F/kills")]"
verdict "a tick with an empty orphan list stops nothing" "$r"
exit $RC

#!/usr/bin/env bash
# Issue 577: `codex-helpers.sh stop <worktree>` also kills each TypeScript language server whose working folder is
# inside the worktree, and `orphans` also lists those whose folder is gone, so a removed worktree leaves none running.
# The servers here are real processes: a symlink to sleep named typescript-language-server, started in each folder, so
# the folder comes from /proc or lsof exactly as in use. A sibling sharing the worktree's name prefix is never touched.
# Each check prints `ok <label>` or `FAIL <label> (why)` and the run goes on, so one break names its own check.
set -uo pipefail
HELPERS=$(cd "$(dirname "$0")/.." && pwd)/codex-helpers.sh
T=$(cd "$(mktemp -d)" && pwd -P); PIDS= RC=0
trap 'kill $PIDS 2>/dev/null; rm -rf "$T"' EXIT
verdict() { if [ -z "$2" ]; then echo "ok $1"; else echo "FAIL $1 ($2)" >&2; RC=1; fi; }
mkdir -p "$T/bin" "$T/wt/sub" "$T/wt-sibling" "$T/other" "$T/gone"
ln -s "$(command -v sleep)" "$T/bin/typescript-language-server"
server() { # <folder> -- a language server whose working folder is <folder>; its pid is in $P
  (cd "$1" && exec "$T/bin/typescript-language-server" 300) & P=$!; PIDS="$PIDS $P"; sleep 0.3; }
alive() { kill -0 "$1" 2>/dev/null; }

server "$T/wt/sub"; IN=$P; server "$T/wt"; AT=$P; server "$T/wt-sibling"; SIB=$P; server "$T/other"; OTH=$P
server "$T/gone"; GONE=$P; rmdir "$T/gone"
mkdir "$T/rm"; server "$T/rm"; RM=$P; rmdir "$T/rm"
ORPH=" $(bash "$HELPERS" orphans) "
r=; case "$ORPH" in *" $GONE "*) ;; *) r="[$ORPH]" ;; esac
verdict "orphans lists a language server whose folder is gone" "$r"
r=; for p in $IN $AT $SIB $OTH; do case "$ORPH" in *" $p "*) r="$r $p listed" ;; esac; done
verdict "orphans spares a language server whose folder exists" "$r"

bash "$HELPERS" stop "$T/wt/" >/dev/null 2>&1; sleep 0.3   # a trailing slash is the same worktree
r=; ! alive "$IN" && ! alive "$AT" || r="inside=$(alive "$IN" && echo alive) top=$(alive "$AT" && echo alive)"
verdict "stop kills a language server running inside the worktree" "$r"
r=; alive "$SIB" || r="killed"
verdict "a language server in a sibling sharing the name prefix survives stop" "$r"
r=; alive "$OTH" || r="killed"
verdict "a language server in an unrelated live folder survives stop" "$r"

# The worktree is removed before stop runs, as merge-unit-local does: the server's folder is gone already.
bash "$HELPERS" stop "$T/rm" >/dev/null 2>&1; sleep 0.3
r=; ! alive "$RM" || r="still running"
verdict "stop kills one whose folder was already removed" "$r"

# A path with a space and regex characters is matched as written.
mkdir -p "$T/a b.c" "$T/aXb.c"; server "$T/a b.c"; SP=$P; server "$T/aXb.c"; RX=$P
bash "$HELPERS" stop "$T/a b.c" >/dev/null 2>&1; sleep 0.3
r=; ! alive "$SP" || r="a path with a space did not match"
alive "$RX" || r="${r:+$r; }the path was matched as a pattern"
verdict "stop matches a worktree path as written" "$r"

# (pass 8) A server node starts with its own options before the script (`node --max-old-space-size=3072 .../tsserver.js`)
# is still found; the word after a node option that takes one (-r) is not the script, and `node -e` runs no script.
# (pass 13) Any option may take its value as the next word (`--inspect-port 9229`, bun's `--preload ./p.ts`): no list
# of value options is kept, so a word after an option that is not a server does not hide the script after it.
# ps, readlink and lsof are stubbed, so no process is started or killed.
r=$(eval "$(sed -n '/^tsservers() {$/,/^}$/p' "$HELPERS")"
  ps() { printf '%s\n' '4242 node --max-old-space-size=3072 /opt/typescript/lib/tsserver.js' \
    '4243 /usr/bin/node -r ts-node/register --inspect /x/typescript-language-server --stdio' \
    '4244 node --require /x/tsserver.js app.js' '4245 node -e tsserver.js' \
    '4246 node --inspect-port 9229 /opt/typescript/lib/tsserver.js' '4247 bun --preload ./p.ts /x/typescript-language-server --stdio' \
    '4248 node --max-old-space-size 3072 /x/tsserver.js'; }
  readlink() { echo /repo/u; }; lsof() { return 1; }; tsservers | tr '\n' ,)
[ "$r" = "4242 /repo/u,4243 /repo/u,4246 /repo/u,4247 /repo/u,4248 /repo/u," ] && r= || r="got [$r]"
verdict "a language server node starts with options before its script is found" "$r"
exit $RC

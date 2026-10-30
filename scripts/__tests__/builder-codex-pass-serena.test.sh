#!/usr/bin/env bash
# builder-codex-pass-serena.test.sh -- issue 470: with Serena on, a reviewer was sent on with no symbol server. A start or
# status that fails (exit 1) is a refusal and no reviewer starts; exit 3 is no Serena on this machine, so the pass goes on and
# the broker gets an empty PP_PASS_SERENA_URL. The stub at COMMANDECK_SERENA_SHARED exits with the code in $TMP/serena-rc.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

echo '{"reviewLoop":{},"serena":true}' > "$REPO/.claude/commandeck.json"
printf '#!/bin/sh\necho "$1" >> "%s/serena.log"\nrc=$(cat "%s/serena-rc")\n[ "$rc" != 0 ] || echo http://127.0.0.1:1/mcp\nexit "$rc"\n' "$TMP" "$TMP" > "$TMP/serena-shared"
export COMMANDECK_SERENA_SHARED=$TMP/serena-shared
# The broker stand-in records the PP_PASS_SERENA_URL it was started with, then serves as the fixture's does.
printf 'import { writeFileSync as w } from "node:fs"; w(process.env.TMPDIR + "/broker-env", "[" + (process.env.PP_PASS_SERENA_URL ?? "unset") + "]");\n' | cat - "$PLUG/scripts/app-server-broker.mjs" > "$TMP/broker.new"
mv "$TMP/broker.new" "$PLUG/scripts/app-server-broker.mjs"
git -C "$REPO" worktree add -q "$TMP/ws/sa" -b builder/sa main && mkdir -p "$TMP/ws/sa/.claude/briefs"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$TMP/ws/sa/.claude/settings.local.json"
printf 'Fix #1.\n' > "$REPO/.claude/briefs/sa-builder-brief.md"; cp "$REPO/.claude/briefs/sa-builder-brief.md" "$TMP/ws/sa/.claude/briefs/sa.md"
echo 'echo work' > "$TMP/ws/sa/b.sh"; git -C "$TMP/ws/sa" add b.sh; git -C "$TMP/ws/sa" commit -qm work # the pass reads nothing without a change
spass() { # <serena stub exit code>: one pass; prints the pass's exit code
  echo "$1" > "$TMP/serena-rc"; rm -rf "$TMP/broker-env" "$CODEX_HOME/sessions" "$TMP/serena.log"
  (cd "$TMP/ws/sa" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-sa-1 STUB_REPLY='VERDICT: GO' \
    timeout 60 bash "$PASS_SH" sa 1 adversarial >"$TMP/out" 2>"$TMP/err"); echo $?
}
ran() { find "$CODEX_HOME/sessions" -name '*thr-sa-1*' 2>/dev/null | wc -l | tr -d ' '; } # the reviewer stub leaves a session record

E1=$(spass 1); R1=$(ran); D1=$(grep -c 'Serena did not start' "$TMP/err"); B1=$([ -e "$TMP/broker-env" ] && echo broker || echo none)
E3=$(spass 3); R3=$(ran); B3=$(cat "$TMP/broker-env" 2>/dev/null)
check "no server, no reviewer (issue 470)" \
  "2 0 1 none | 1 []" "$E1 $R1 $D1 $B1 | $([ "$R3" -gt 0 ] && echo 1) $B3"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

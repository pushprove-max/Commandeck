#!/usr/bin/env bash
# A screen read is a viewport: prose, a bare fence, then a verdict line is either a cropped fence closing above the
# pane's own verdict, or a fixture verdict still streaming inside a fence that just opened. That read as GO, and a
# GO merges. Pinned (main's ruling): on such a screen a GO is not read as the verdict, any other verdict is, and a
# GO outside a fence that closed on screen still reads as GO.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
git init -q -b main "$T/p"
# Orca: no accumulated stream (as for an agent pane), the screen is $T/screen; the pane is in no worktree it knows.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"terminal read"*"--screen"*) jq -n --rawfile s "$T/screen" '{result: {terminal: {tail: \$s}}}' ;;
  *"terminal read"*) echo '{"result":{"terminal":{"tail":""}}}' ;;
  *) echo '{"ok":true,"result":{"terminals":[]}}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
# verdict <screen>: the canonical VERDICT line read-verdict.sh prints, or "none" when it reads no verdict (exit 3;
# its "last lines" dump then still shows the screen's verdict-shaped line)
verdict() { local out rc; printf '%b' "$1" > "$T/screen"
  out=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/sc" \
    COMMANDECK_WORKSPACES="$T/ws" timeout 20 bash "$REAL/scripts/read-verdict.sh" term_r 2>/dev/null); rc=$?
  [ "$rc" = 3 ] && echo none || grep -m1 '^VERDICT:' <<<"$out"; }
check "prose, a bare fence, then VERDICT: GO: no verdict" none "$(verdict 'Reviewing.\n```\nVERDICT: GO\n')"
check "the same shape with NO-GO: NO-GO" "VERDICT: NO-GO" "$(verdict 'code\n```\nVERDICT: NO-GO\n')"
check "a fenced sample that closes, then the reply's own GO: GO" "VERDICT: GO" \
  "$(verdict 'Sample:\n```bash\nVERDICT: NO-GO\n```\nAll fixed.\nVERDICT: GO\n')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

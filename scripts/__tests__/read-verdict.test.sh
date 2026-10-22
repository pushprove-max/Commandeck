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
  *"terminal list"*) [ -e "$T/listed" ] && echo '{"ok":true,"result":{"terminals":[{"handle":"term_r","worktreePath":"$T/p"}]}}' \
    || echo '{"ok":true,"result":{"terminals":[]}}' ;;
  *) echo '{"ok":true,"result":{"terminals":[]}}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
# verdict <screen>: the canonical VERDICT line read-verdict.sh prints, or "none" when it reads no verdict (exit 3;
# its "last lines" dump then still shows the screen's verdict-shaped line)
verdict() { local out rc; printf '%b' "$1" > "$T/screen"
  out=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR ${PROFILE:+CLAUDE_CONFIG_DIR="$PROFILE"} HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/sc" \
    COMMANDECK_WORKSPACES="$T/ws" timeout 20 bash "$REAL/scripts/read-verdict.sh" term_r 2>/dev/null); rc=$?
  [ "$rc" = 3 ] && echo none || grep -m1 '^VERDICT:' <<<"$out"; }
check "prose, a bare fence, then VERDICT: GO: no verdict" none "$(verdict 'Reviewing.\n```\nVERDICT: GO\n')"
check "the same shape with NO-GO: NO-GO" "VERDICT: NO-GO" "$(verdict 'code\n```\nVERDICT: NO-GO\n')"
check "a fenced sample that closes, then the reply's own GO: GO" "VERDICT: GO" \
  "$(verdict 'Sample:\n```bash\nVERDICT: NO-GO\n```\nAll fixed.\nVERDICT: GO\n')"
# Every reader of the printed line (seat.sh, the merge) matches one space after the colon; read-verdict accepts any.
check "a verdict with two spaces after the colon is printed in one canonical form" "VERDICT: GO" "$(verdict 'Done.\nVERDICT:  GO\n')"
check "a verdict with no space after the colon is printed in one canonical form" "VERDICT: GO" "$(verdict 'Done.\nVERDICT:GO\n')"
# seat.sh binds a Codex seat's log into its record as a path (session=/.../rollout.jsonl). For a pane Orca names no
# agent for, that path is no Claude session id: the seat's Claude log is still found by its launch time.
touch "$T/listed"; mkdir -p "$T/sc" "$T/home/.claude/projects/$(printf '%s' "$T/p" | tr -c 'A-Za-z0-9' '-')"
printf 'handle=term_r\ntask=task_r\nrole=plan-author\nlaunched=%s\nsession=%s\n' $(($(date +%s) - 60)) "$T/codex/rollout.jsonl" > "$T/sc/seat-r.txt"
jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{type: "assistant", timestamp: $t, message: {content: [{type: "text", text: "Done.\nVERDICT: NO-GO"}]}},
  {type: "system", subtype: "turn_duration", timestamp: $t}' > "$T/home/.claude/projects/$(printf '%s' "$T/p" | tr -c 'A-Za-z0-9' '-')/s1.jsonl"
check "a record's bound Codex log path is not read as a Claude session id" "VERDICT: NO-GO" "$(verdict 'Working.\n')"
# Issue 291: under an account profile (CLAUDE_CONFIG_DIR) Claude Code writes its transcripts and session files in that
# folder, and ~/.claude holds none: every seat read there was "not measured".
mkdir -p "$T/prof"; mv "$T/home/.claude/projects" "$T/prof/"
check "issue 291: a seat's transcript is read from CLAUDE_CONFIG_DIR" "VERDICT: NO-GO" "$(PROFILE=$T/prof verdict 'Working.\n')"
# A stand-in claude: a copy of sleep under that name, carrying a pane's handle, started from a subshell that exits so
# it has no claude ancestor even when this test runs in a Claude pane.
cp "$(command -v sleep)" "$T/bin/claude"
( ORCA_TERMINAL_HANDLE=term_s$$ "$T/bin/claude" 30 </dev/null >/dev/null 2>&1 & echo $! > "$T/pid" ); CP=$(cat "$T/pid")
trap 'kill "$CP" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude/sessions" "$T/prof/sessions"
echo '{"sessionId":"s-home"}' > "$T/home/.claude/sessions/$CP.json"; echo '{"sessionId":"s-prof"}' > "$T/prof/sessions/$CP.json"
sleep 0.3
sess() { env -u CLAUDE_CONFIG_DIR ${PROFILE:+CLAUDE_CONFIG_DIR="$PROFILE"} HOME="$T/home" bash "$REAL/scripts/read-verdict.sh" --session term_s$$ 2>/dev/null; }
check "issue 291: a pane's session is read from CLAUDE_CONFIG_DIR when it is set, from ~/.claude when not" "s-prof s-home" \
  "$(PROFILE=$T/prof sess) $(sess)"
# Issue 225: two NO-GOs in a row on one finding class are a loop, not progress: --repeat-class names the class.
# rf <round> <verdict> <finding line> -- a round file as builder-codex-pass.sh writes it.
B=$T/briefs; mkdir -p "$B"
rf() { printf 'Pass: review\n%s\n\nVERDICT: %s\n' "$3" "$2" > "$B/u-r$1-reports.md"; }
repeat() { bash "$REAL/scripts/read-verdict.sh" --repeat-class "$B/u-r4-reports.md" 2>&1; }
rf 3 NO-GO '- [P2] (class: old-format-case) a case -- a.sh:1 -- why -- input'
rf 4 NO-GO '- [P1] (class: old-format-case) another case -- b.sh:2 -- why -- input'
check "two NO-GOs in a row sharing a class print REPEAT CLASS" "REPEAT CLASS: old-format-case (r3, r4)" "$(repeat)"
rf 4 NO-GO '- [P1] (class: lost-reply) another case -- b.sh:2 -- why -- input'
check "two NO-GOs on different classes print nothing" "" "$(repeat)"
rf 3 GO '- [P3] (class: lost-reply) a nit -- a.sh:1 -- why -- input'
check "a GO before is no repeat" "" "$(repeat)"
# Every finding, P3 too, blocks the merge and gets a fix round, so a P3 class that comes back is a loop as well.
rf 3 NO-GO '- [P3] (class: lost-reply) a nit -- a.sh:1 -- why -- input'
check "two NO-GOs on one class at P3 print REPEAT CLASS" "REPEAT CLASS: lost-reply (r3, r4)" "$(repeat)"
# The gate counts a "(class:" line with no level, and any level form, as a finding, so a class that comes back in
# those forms is the same loop (class finding-reader-drift, pass 6).
rf 3 NO-GO '- (class: probe) bug -- a.sh:1 -- wrong -- bash a.sh'
rf 4 NO-GO '- (class: probe) bug -- a.sh:1 -- wrong -- bash a.sh'
check "two NO-GOs on one class with no level print REPEAT CLASS" "REPEAT CLASS: probe (r3, r4)" "$(repeat)"
rf 3 NO-GO 'Finding: (P1) (class:probe) mid-line -- a.sh:1 -- why -- input'
rf 4 NO-GO '1. [**P2**] (class: probe) numbered -- b.sh:2 -- why -- input'
check "two NO-GOs on one class in other level forms print REPEAT CLASS" "REPEAT CLASS: probe (r3, r4)" "$(repeat)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

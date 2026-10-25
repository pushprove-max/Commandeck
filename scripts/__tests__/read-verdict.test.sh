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
# Ordinal `prompt` (main-watch.sh reported()): the epoch of the seat's latest prompt, so a worker_done made before it is
# an earlier turn's report. A system-reminder-only user row is no prompt; no log or no prompt is exit 3.
L=$T/home/.claude/projects/$(printf '%s' "$T/p" | tr -c 'A-Za-z0-9' '-')/s1.jsonl
P1=$(( $(date +%s) - 50 )); P2=$(( P1 + 20 )); P3=$(( P2 + 10 ))
{ jq -cn --arg t "$(date -u -r "$P1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$P1" +%Y-%m-%dT%H:%M:%SZ)" '{type: "user", timestamp: $t, message: {content: "first task"}}'
  jq -cn --arg t "$(date -u -r "$P2" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "@$P2" +%Y-%m-%dT%H:%M:%S).500Z" '{type: "user", timestamp: $t, message: {content: [{type: "text", text: "follow up"}]}}'
  jq -cn --arg t "$(date -u -r "$P3" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$P3" +%Y-%m-%dT%H:%M:%SZ)" '{type: "user", timestamp: $t, isMeta: true, message: {content: "<system-reminder>x</system-reminder>"}}'; cat "$L"; } > "$L.new" && mv "$L.new" "$L"
pr() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/sc" \
    COMMANDECK_WORKSPACES="$T/ws" timeout 20 bash "$REAL/scripts/read-verdict.sh" term_r 5 "" "" "" "" prompt "$(( $(date +%s) - 60 ))" 2>/dev/null; echo ":$?"); }
check "ordinal prompt prints the epoch of the seat's latest prompt, not a meta row's" "$P2:0" "$(pr | tr -d '\n')"
mv "$L" "$L.off"; check "ordinal prompt with no session log exits 3" ":3" "$(pr | tr -d '\n')"; mv "$L.off" "$L"
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
# Host issue 3038: the pane's environment is read whole on either host. Each case runs once per reader, with `uname`
# stubbed and the reader's input injected under the stand-in claude's pid, whose real environment carries none of these
# values: only the injected input can make a case pass, so the host that runs this file does not pick the reader tested.
# Catches: the Darwin branch back to `ps -Eww | tr` (an entry split at its spaces), or the Linux /proc read changed.
mkdir -p "$T/unamebin" "$T/home2"
inject() { # <Linux|Darwin> <entry>... -- the pid's environment as that host's reader takes it
  local os=$1 e; shift
  printf '#!/bin/sh\necho %s\n' "$os" > "$T/unamebin/uname"; chmod +x "$T/unamebin/uname"
  rm -rf "$T/proc" "$T/procargs"; mkdir -p "$T/proc/$CP" "$T/procargs"
  if [ "$os" = Linux ]; then for e in "$@"; do printf '%s\0' "$e"; done > "$T/proc/$CP/environ"
  else { printf '\001\000\000\000/bin/claude\0\0\0claude\0'; for e in "$@"; do printf '%s\0' "$e"; done; printf '\0'; } > "$T/procargs/$CP"; fi
}
session_of() { # <handle> -- the session the injected environment links to that pane
  env -u CLAUDE_CONFIG_DIR PATH="$T/unamebin:$PATH" HOME="$T/home" READ_VERDICT_PROC="$T/proc" READ_VERDICT_PROCARGS="$T/procargs" \
    bash "$REAL/scripts/read-verdict.sh" --session "$1" 2>/dev/null
}
for OS in Linux Darwin; do
  inject "$OS" "ORCA_TERMINAL_HANDLE=term_inj_$OS" "CLAUDE_CONFIG_DIR=$T/my profile" "X=a ORCA_TERMINAL_HANDLE=term_decoy"
  check "$OS reader: an entry that is the handle links the pane to its session" "s-home" "$(session_of "term_inj_$OS")"
  check "$OS reader: a handle inside another variable's value does not link" "" "$(session_of term_decoy)"
done
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
# Issue 362: given an earlier round file, the comparison is with that round whatever its verdict, so a class that comes back
# after a GO round (or after a pass in between) is the same flaw seen again.
repeat_with() { bash "$REAL/scripts/read-verdict.sh" --repeat-class "$B/u-r4-reports.md" "$B/u-r$1-reports.md" 2>&1; }
rf 4 NO-GO '- [P2] (class: lost-reply) back again -- b.sh:2 -- why -- input'
rf 2 NO-GO '- [P2] (class: lost-reply) first time -- a.sh:1 -- why -- input'
check "an earlier round that is not the one before, sharing the class, prints REPEAT CLASS with both rounds" "REPEAT CLASS: lost-reply (r2, r4)" "$(repeat_with 2)"
rf 2 GO '- [P3] (class: lost-reply) a nit -- a.sh:1 -- why -- input'
check "an earlier round that ended GO still counts when it names the class" "REPEAT CLASS: lost-reply (r2, r4)" "$(repeat_with 2)"
rf 2 NO-GO '- [P2] (class: other) something else -- a.sh:1 -- why -- input'
check "an earlier round of another class prints nothing" "" "$(repeat_with 2)"
rf 4 GO '- [P3] (class: lost-reply) a nit -- b.sh:2 -- why -- input'
rf 2 NO-GO '- [P2] (class: lost-reply) first time -- a.sh:1 -- why -- input'
check "this round must itself end NO-GO: a GO round names no repeat" "" "$(repeat_with 2)"
# Issue 353, pinned: the Builder's done marker is read as the last line of its latest message, so a marker after a
# quoted VERDICT line counts, and a VERDICT line after the marker (the marker no longer last) does not.
WM=$T/wtm; LM=$T/home/.claude/projects/$(printf '%s' "$WM" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$LM"
reply() { # <message text> -- one Claude turn in the worktree's log
  { jq -cn --arg t "$(date -u -d '@1000' +%Y-%m-%dT%H:%M:%SZ)" '{type: "user", timestamp: $t, message: {content: "build it"}}'
    jq -cn --arg t "$(date -u -d '@1010' +%Y-%m-%dT%H:%M:%SZ)" --arg x "$1" '{type: "assistant", timestamp: $t, message: {id: "m1", content: [{type: "text", text: $x}]}}'
    jq -cn --arg t "$(date -u -d '@1020' +%Y-%m-%dT%H:%M:%SZ)" '{type: "system", subtype: "turn_duration", timestamp: $t}'; } > "$LM/s1.jsonl"; }
mark() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/sc" \
    COMMANDECK_WORKSPACES="$T/ws" timeout 20 bash "$REAL/scripts/read-verdict.sh" --state --worktree "$WM" --agent claude --launched 1 --marker U-DONE 2>/dev/null | grep -m1 '^marker='); }
reply $'Pass 3 ended.\nVERDICT: GO\nU-DONE'
check "a marker alone on the last line after a VERDICT line reads marker=1" "marker=1" "$(mark)"
reply $'U-DONE\nVERDICT: GO'
check "a marker followed by a VERDICT line reads marker=0" "marker=0" "$(mark)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

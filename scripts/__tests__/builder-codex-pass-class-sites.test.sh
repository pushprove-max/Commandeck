#!/usr/bin/env bash
# Host change (owner order 2026-10-25): a fixer that chose its own search for the same pattern searched its fix's shape,
# not the bug's, and the bug came back. A finding's `Class search: rg ...` line, the reviewer's; the pass runs it as rg
# with no shell, hands the hits to the fix round, and the next pass refuses until every hit is in Sites checked. With no
# rg the pass refuses (the owner's answer). The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"
rawpass() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 STUB_REPLY="$3" bash "$PASS_SH" "$U" "$1" "$2" >"$TMP/out" 2>"$TMP/err"); echo $?; }
printf 'handle=term_frs\ntask=task_frs\nunit=%s\nrole=builder\nsession=old-sid\n' "$U" > "$SC/seat-$U-builder.txt"
printf 'echo base\n' > "$W/a.sh"
pass 1 adversarial
printf 'echo built\n' > "$W/a.sh"; printf 'built\n' > "$W/b.sh"; printf 'other\n' > "$W/c.sh"
fpass "$W" 2 review $'- [P1] (class: stale-read) stale read -- a.sh:1 -- why -- cmd\nClass search: rg -n built a.sh b.sh c.sh\nVERDICT: NO-GO' >/dev/null
# The prompt line that asks for it lands in a follow-up unit (main's answer, fix round 10): here the stub writes one.
check "the pass runs the reviewer's search and keeps every hit as path:line" "a.sh:1 b.sh:1" "$(paste -sd' ' - < "$B/$U-r2-class-sites.txt" 2>/dev/null)"
check "the fix brief lists the hits under Class sites" "1 1" "$(hand 2 | grep -c "^## Class sites (from the reviewers' searches)") $(hand 2 | grep -cx '  - b.sh:1')"
# The Mac's preflight puts Homebrew's folders back on PATH: an empty Homebrew folder keeps rg off it.
chk() { (cd "$W" && TMPDIR=$TMP PATH=${2:-$TMP/cli:$PATH} COMMANDECK_BREW_PREFIX=${2:+$TMP/nobrew} COMMANDECK_MAIN=$REPO bash "$PASS_SH" --check "$U" "$1" review >/dev/null 2>"$TMP/err"); echo $?; }
printf '\n## Sites checked (pass 2)\nSearch: rg -n built .\n- a.sh:1 fixed\n\n## New code checked (pass 2)\n- none, a fixture\n' >> "$B/$U-evidence.md"
check "the next pass refuses while a hit is missing from Sites checked, and names only that hit" "2 1 0" \
  "$(chk 3) $(grep -c 'b.sh:1' "$TMP/err") $(grep -c 'a.sh:1' "$TMP/err")"
sed -i.bak 's/^- a.sh:1 fixed$/&\n- b.sh:1 not affected, a fixture with no read/' "$B/$U-evidence.md"; rm -f "$B/$U-evidence.md.bak"
check "...and starts once every hit is listed" 0 "$(chk 3)"
# The command is the reviewer's text: it runs as rg with no shell, and rg's program-running flags are refused. A search
# under KNOWN GAPS: has no finding above it.
R3=$'- [P2] (class: x) x -- a.sh:1 -- why -- cmd\nClass search: rg --pre cat built a.sh\n- [P2] (class: x) y -- a.sh:1 -- why -- cmd\nClass search: rg -n nomatch a.sh\nClass search: rg -nz built a.sh\n- [P2] (class: x) z -- a.sh:1 -- why -- cmd\nClass search: cat a.sh; touch pwned\nKNOWN GAPS:\n- a gap -- a.sh:1 -- needs a bypass\nClass search: rg -n built a.sh\nVERDICT: NO-GO'
printf 'other two\n' > "$W/c.sh"; rawpass 3 review "$R3" >/dev/null
check "--pre, -z in a flag cluster, a search missing its own finding, a non-rg command and a search under KNOWN GAPS are each refused, run nothing and owe nothing" "5 0 0" \
  "$(grep -c '^- refused' "$B/$U-r3-class-sites.md" 2>/dev/null) $(wc -l < "$B/$U-r3-class-sites.txt" | tr -d ' ') $([ -e "$W/pwned" ] && echo 1 || echo 0)"
# Run from a real pane, this file once sent main a real "no fix hand-off" question: the fixture clears the pane handle,
# so the NO-GO pass above saw none, and its notice to main stayed in the fixture (the orca-ide stub, or the scratch queue).
check "a test's pass has no pane handle, and its notice to main stays in the fixture" "1 1" \
  "$(grep -c 'NO FIX HAND-OFF after pass 3: no Orca handle' "$TMP/out") $(cat "$TMP/orca-calls" "$SC"/queue/*.jsonl 2>/dev/null | grep -c 'no fix hand-off after pass 3')"
# The owner's answer (2026-10-25): with no rg the pass refuses loudly, so no class search is skipped unseen.
NORG=$TMP/norg; mkdir -p "$NORG" "$TMP/nobrew"; IFS=: read -ra DIRS <<<"$TMP/cli:$PATH"
for d in "${DIRS[@]}"; do [ ! -d "$d" ] || for f in "$d"/*; do [ -e "$NORG/${f##*/}" ] || ln -s "$f" "$NORG/" 2>/dev/null; done; done; rm -f "$NORG/rg"
check "a pass with no rg on PATH is refused, naming rg, and starts no round" "2 1 no" \
  "$(chk 4 "$NORG") $(grep -c 'no rg (ripgrep) on PATH' "$TMP/err") $([ -e "$B/$U-r4-reports.md" ] && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

# The setup the merge-queue*.test.sh files share (split so each finishes under the runner's 120 s cap): the
# merge-unit-local fixture, and a check that counts its runs and is red on a tree holding break.txt. The closing
# pass runs it whole beforehand. Sourced, with REAL, PASS, FAIL and check set by the caller.
. "$(dirname "${BASH_SOURCE[0]}")/merge-unit-local-setup.sh"
QUEUE=$REAL/scripts/merge-queue.sh
mkdir -p "$REPO/.claude"
jq -n --arg c "echo run >> $TMP/check-calls; [ ! -e break.txt ]" '{testCommand: $c, fullSuiteBeforeFinal: true}' > "$REPO/.claude/commandeck.json"
CFG=$(cat "$REPO/.claude/commandeck.json")
runs() { grep -c . "$TMP/check-calls"; }
closed() { go "$1"; pass "$1" 2 final; } # <unit>: a first pass, then a closing pass whose suite runs green
on_main() { echo "$2" > "$REPO/$1"; git -C "$REPO" add "$1"; git -C "$REPO" commit -qm "main: $1"; } # <path> <text>
sha() { git -C "$COMMANDECK_WORKSPACES/$1" rev-parse HEAD; }
# add <unit> <file>: the unit commits that file.
add() { echo x > "$COMMANDECK_WORKSPACES/$1/$2"; git -C "$COMMANDECK_WORKSPACES/$1" add "$2"; git -C "$COMMANDECK_WORKSPACES/$1" commit -qm "feat($1): adds $2"; }
# Passes 4 and 5's findings, one case per stdin line "<what>|<how>": two closed units each green alone, red
# together, with a check that reads the flag files no name points to in that way. The first merge reuses (main has
# not moved); the second's run is on another tree, so its check runs and refuses the merge.
pattern_cases() {
  local n=0 what how
  while IFS='|' read -r what how <&3; do
    n=$((n + 1))
    jq --arg c "echo run >> $TMP/check-calls; $(printf '%b' "$how"); [ \"\$#\" -ne 2 ]" '.testCommand = $c' <<<"$CFG" > "$REPO/.claude/commandeck.json"
    mk "ea$n"; mk "eb$n"; add "ea$n" a.flag; add "eb$n" b.flag; closed "ea$n"; closed "eb$n"; : > "$TMP/check-calls"
    check "a check that finds files by $what: the second merge runs its check and refuses" "0 1 1" "$(merge "ea$n") $(merge "eb$n") $(runs)"
    git -C "$REPO" rm -q --ignore-unmatch a.flag b.flag; git -C "$REPO" commit -qm "main: drop the flags"
  done 3<&0 </dev/null
  echo "$CFG" > "$REPO/.claude/commandeck.json"
}

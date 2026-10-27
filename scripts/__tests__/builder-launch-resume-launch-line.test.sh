#!/usr/bin/env bash
# builder-launch-resume-launch-line.test.sh -- issue 234: a unit opened on an order that never named it is refused; the
# batch's Launch line must name this unit as new. The fixture is builder-launch-resume.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"

# Issue 234: a unit opened on an order that never named it. The batch quotes the order, and its Launch line must
# name this unit as new; adding work to a unit is builder-add-work.sh's.
# order <unit> <launch line> -- a launch of <unit> on a batch with that Launch line ('' for none); RC and $T/out as build's.
order() { : > "$T/seats"; : > "$T/orca.log"; batchfor "$1" "$2"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
  bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
order u11 ''
check "a batch with no Launch line is refused before anything opens" "2:1:0:0" "$RC:$(grep -c 'REFUSED: .* has no Launch line' "$T/out"):$(grep -c . "$T/seats"):$(grep -c . "$T/orca.log")"
check "the refusal says the Order line must quote the owner's yes naming the unit or its issues (issue 287)" 1 \
  "$(grep -c "the Order line must quote the owner's yes naming this unit or its issues" "$T/out")"
order u12 'Launch: add to u2'
check "a batch that adds to a unit is refused, pointing to builder-add-work.sh" "2:1:0" "$RC:$(grep -c 'REFUSED: .*adds work to u2: run builder-add-work.sh u2' "$T/out"):$(grep -c . "$T/seats")"
order u13 'Launch: new unit u99'
check "a batch whose order names another unit is refused" "2:1:0" "$RC:$(grep -c "REFUSED: .*names u99, not u13" "$T/out"):$(grep -c . "$T/seats")"
order u14 'Launch: new unit u14'
check "a batch whose Launch line names this unit as new opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u14' "$T/seats")"

# Issue 341 (F1): a batch states its data design (what state it adds, who owns it, when it resets, what a retry runs) before
# any Builder opens. A missing section, an empty one, and the template's placeholder alone are refused.
dd() { : > "$T/seats"; : > "$T/orca.log"; batchfor "$1"; sed -i.bak '/^## Data design$/,/^## What can go wrong$/{/^## What can go wrong$/!d;}' "$T/batch.md"; rm -f "$T/batch.md.bak"
  [ -z "${2-}" ] || printf '\n## Data design\n\n%s\n' "$2" >> "$T/batch.md"
  (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
    bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
# Issue 362: the 0.46.0 exception (a batch with no Data design heading at all opened, and its Builder wrote the design) is
# gone: a missing heading is refused like an empty section or a placeholder-only one, and no Builder opens.
dd u15
check "a batch with no Data design section is refused and opens no Builder" "2:1:0" "$RC:$(grep -c 'REFUSED: .* has no Data design section' "$T/out"):$(grep -c 'launch builder' "$T/seats")"
dd u16 ''
dd u16 ' '
check "a batch whose Data design section is empty is refused" "2:1" "$RC:$(grep -c 'REFUSED: .* has no Data design section' "$T/out")"
dd u17 $'Required: builder-launch.sh refuses a batch without it. Say what state the batch adds.\n\n- <piece of state>: lives in <where>; written by <who>; reset when <when>'
check "a batch with only the template's guidance and placeholder is refused" "2:1" "$RC:$(grep -c 'REFUSED: .* has no Data design section' "$T/out")"
dd u18 '- the pass hand-off file: lives in the unit worktree; written by the pass script; rewritten each round; a retry rewrites it whole'
check "a batch that fills the section opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u18' "$T/seats")"
dd u19 'none: no state is added or changed'
check "a batch that says none, with the reason, opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u19' "$T/seats")"
# Decision G4-3: a batch in the 0.46.0 shape (no Data design, no What can go wrong heading) has no compatibility branch,
# because 0 such batches were unlaunched at upgrade. It is refused with each missing heading named in turn, and no Builder opens.
: > "$T/seats"; batchfor u20; awk '/^## / { omit = ($0 == "## Data design" || $0 == "## What can go wrong") } !omit' "$T/batch.md" > "$T/legacy.md"
legacy() { (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
  bash "$T/plug/scripts/builder-launch.sh" u20 "$T/legacy.md" </dev/null >"$T/out" 2>&1); RC=$?; }
legacy
check "a 0.46.0-shape batch is refused, the Data design heading named as the fix, no Builder" "2:1:0" \
  "$RC:$(grep -c "REFUSED: .* has no Data design section (a '## Data design' heading" "$T/out"):$(grep -c 'launch builder' "$T/seats")"
printf '\n## Data design\n\nnone: no state is added or changed\n' >> "$T/legacy.md"; legacy
check "... with its Data design written, refused next for What can go wrong, that heading named, no Builder" "2:1:0" \
  "$RC:$(grep -c "REFUSED: neither .* has a What can go wrong section .*'## What can go wrong' heading" "$T/out"):$(grep -c 'launch builder' "$T/seats")"

# Issue 368: a Builder reaches the main that launched it, wherever that runs. record_main_pane (the launch's own
# function) on a hand-written settings file and a stubbed Orca pane list.
RMP=$(sed -n '/^record_main_pane()/,/^}/p' "$REAL/scripts/builder-launch.sh")
mkdir -p "$T/lbin"; OTHER=$T/other-main; mkdir -p "$OTHER"
cat > "$T/lbin/orca-ide" <<EOS
#!/usr/bin/env bash
[ -e "$T/list-down" ] && exit 1
jq -n --arg o "$OTHER" --arg p "$P" '{result: {terminals: [{handle: "term_other", worktreePath: \$o}, {handle: "term_own", worktreePath: (\$p + "/")}]}}'
EOS
chmod +x "$T/lbin/orca-ide"
SETDEF='{"env":{"COMMANDECK_BUILDER":"1"}}'
rmp() { # <handle> [settings json] -- the settings file after a launch from that pane
  printf '%s\n' "${2:-$SETDEF}" > "$T/set.json"
  (cd "$P" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$P" PATH="$T/lbin:$PATH" ORCA_TERMINAL_HANDLE="$1" bash -c '. "$0/scripts/paths.sh" >/dev/null; '"$RMP"'; record_main_pane "$1"' "$REAL" "$T/set.json") ; jq -c .env "$T/set.json"; }
check "a launch from a pane in another checkout records that checkout as COMMANDECK_MAIN_PANE_DIR, and keeps the Builder's other env" "{\"COMMANDECK_BUILDER\":\"1\",\"COMMANDECK_MAIN_PANE_DIR\":\"$OTHER\"}" "$(rmp term_other)"
check "a launch from main's own checkout records none (a trailing slash on the pane's folder is the same folder)" '{"COMMANDECK_BUILDER":"1"}' "$(rmp term_own)"
check "a relaunch from main's own checkout drops the earlier record" '{"COMMANDECK_BUILDER":"1"}' \
  "$(rmp term_own "{\"env\":{\"COMMANDECK_BUILDER\":\"1\",\"COMMANDECK_MAIN_PANE_DIR\":\"$OTHER\"}}")"
check "a launch from a pane Orca does not list records none" '{"COMMANDECK_BUILDER":"1"}' "$(rmp term_gone)"
touch "$T/list-down"
check "a launch while Orca's list cannot be read records none, and does not fail" '{"COMMANDECK_BUILDER":"1"}' "$(rmp term_other)"
rm -f "$T/list-down"

# Issue 394: options in any position. args <word>... -- a launch with those words as given; RC and $T/out as build's.
args() { : > "$T/seats"; : > "$T/orca.log"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
  bash "$T/plug/scripts/builder-launch.sh" "$@" </dev/null >"$T/out" 2>&1); RC=$?; }
DRYOK=
for pos in 1 2 3; do
  batchfor u21
  case $pos in 1) args --dry-run u21 "$T/batch.md" ;; 2) args u21 --dry-run "$T/batch.md" ;; 3) args u21 "$T/batch.md" --dry-run ;; esac
  DRYOK+="$RC:$(grep -c . "$T/seats"):$(grep -c '^#### Launch$' "$T/out"):$([ -e "$WS/u21" ] && echo wt || echo none) "
done
check "dry-run in every position launches nothing" "0:0:1:none 0:0:1:none 0:0:1:none " "$DRYOK"
batchfor u22; args u22 "$T/batch.md" --keep billing
check "keep after the batch takes effect" "0:billing" "$RC:$(cat "$T/keep-at-open" 2>/dev/null)"
batchfor u23; args u23 "$T/batch.md" stray
check "an extra argument is refused" "2:1:0" "$RC:$(grep -c '^extra argument stray$' "$T/out"):$(grep -c . "$T/seats")"
batchfor u24; args u24 --bogus "$T/batch.md"
check "an unknown option is refused naming it" "2:1:0" "$RC:$(grep -c '^unknown option --bogus$' "$T/out"):$(grep -c . "$T/seats")"
batchfor u25; args u25 "$T/batch.md" --model
check "a trailing option with no value is refused" "2:1:1" "$RC:$(grep -c '^--model needs a value$' "$T/out"):$(grep -c '^usage: builder-launch.sh' "$T/out")"
batchfor u26; args --skip-plan u26 "$T/batch.md" --reason --dry-run
check "a value option given a flag is refused and launches nothing" "2:1:0:0:none" \
  "$RC:$(grep -c '^--reason needs a value$' "$T/out"):$(grep -c . "$T/seats"):$(grep -c 'worktree create' "$T/orca.log"):$([ -e "$WS/u26" ] && echo wt || echo none)"

# Issue 392: a plan names each mockup on a Mockup: line, and the batch (the Builder's brief) carries it.
# mockplan <unit> <plan's extra lines> [batch's extra line] -- the unit's plan committed on main, its batch naming it.
mockplan() { printf 'plan\n%s\n%s\n' "$PSZ" "$2" > "$P/.claude/plans/$1.md"; git -C "$P" add -A .claude/plans && git -C "$P" commit -qm "plan $1"
  batchfor "$1"; sed -i.bak "s#\.claude/plans/toy\.md#.claude/plans/$1.md#" "$T/batch.md"; rm -f "$T/batch.md.bak"
  [ -z "${3-}" ] || printf '\n%s\n' "$3" >> "$T/batch.md"; }
mkdir -p "$P/docs"; echo png > "$P/docs/m1.png"
mockplan u27 'Mockup: docs/m1.png'; args u27 "$T/batch.md"
check "a plan mockup missing from the batch is refused" "2:1:0" \
  "$RC:$(grep -c 'REFUSED: .claude/plans/u27.md names the mockup docs/m1.png (a Mockup: line) and .* does not carry it' "$T/out"):$(grep -c . "$T/seats")"
mockplan u28 'Mockup: docs/none.png' 'Mockup: docs/none.png'; args u28 "$T/batch.md"
check "a mockup file that does not exist is refused" "2:1:0" "$RC:$(grep -c 'REFUSED: .* names the mockup docs/none.png, which does not exist' "$T/out"):$(grep -c . "$T/seats")"
mockplan u29 'Mockup: docs/m1.png' 'Mockup: docs/m1.png'; args u29 "$T/batch.md"
check "a plan mockup in the batch launches" "0:1" "$RC:$(grep -cx 'launch builder u29' "$T/seats")"
mockplan u30 $'```\nMockup: docs/fenced.png\n```'; args u30 "$T/batch.md"
check "a fenced Mockup line is not a mockup" "0:1" "$RC:$(grep -cx 'launch builder u30' "$T/seats")"

# Issue 398: a plan or batch line that states existing placeholder UI as context is flagged on stderr; the launch goes on.
mockplan u31 'The export page shows a Coming soon banner today.'; args u31 "$T/batch.md"
check "a plan that describes placeholder UI as context is flagged and still launches" "0:1:1" \
  "$RC:$(grep -c '^FLAG: .claude/plans/u31.md line 3 describes placeholder UI: an open problem, not a fact' "$T/out"):$(grep -cx 'launch builder u31' "$T/seats")"
mockplan u32 '' 'Context: <Button disabled={true}>Export</Button> already ships as a layout stub.'; args u32 "$T/batch.md"
check "a batch line naming a literal disabled control is flagged" "0:1:1" \
  "$RC:$(grep -c '^FLAG: ' "$T/out"):$(grep -c '^FLAG: .*batch.* line [0-9]* describes placeholder UI' "$T/out")"
mockplan u33 'Placeholder: web/src/X.tsx | <p>Coming soon</p> | its feature ships next release'; args u33 "$T/batch.md"
check "a plan's Placeholder line is not flagged" "0:0" "$RC:$(grep -c '^FLAG: ' "$T/out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

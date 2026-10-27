#!/usr/bin/env bash
# timeout: 600
# covers: scripts/merge-unit-local.sh hooks/lib/screen-code.sh
# Issue 392: a diff touching screen code (the project's screenPaths, web/src/ by default) merges only with a
# ## Screenshots row in the evidence. Issue 398: it also merges only without placeholder UI the plan or main's rulings
# did not name on a Placeholder: line. Every refusal is step 1, before the rebase. Each case is one unit; main is put
# back to its first commit after each, so a merged file never meets the next case's.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

WS=$COMMANDECK_WORKSPACES H0=$(git -C "$REPO" rev-parse HEAD)
SHOT=$TMP/shot.png MOCK=$TMP/mock.png; echo png > "$SHOT"; echo png > "$MOCK"
PLAN="" RULINGS="" EV=shot HEAD='##'
# cu <unit> <path> <content>: a unit adding one file, its evidence per $EV, the plan on main per $PLAN, main's rulings per $RULINGS.
cu() {
  local u=$1 ev=$WS/$1/.claude/briefs/$1-evidence.md
  if [ -n "$PLAN" ]; then mkdir -p "$REPO/.claude/plans"; printf '%s\n' "$PLAN" > "$REPO/.claude/plans/$u.md"; git -C "$REPO" add .claude/plans; git -C "$REPO" commit -qm "plan $u"; fi
  if [ -n "$RULINGS" ]; then mkdir -p "$REPO/.claude/briefs"; printf '%s\n' "$RULINGS" > "$REPO/.claude/briefs/$u-main-rulings.md"; fi
  mk "$u"
  # The worktree's copy of the plan approves nothing: only the plan as committed on local main counts.
  [ -z "$PLAN" ] || printf 'the worktree copy names no Placeholder line\n' > "$WS/$u/.claude/plans/$u.md"
  printf '%s Plan\n.claude/plans/%s.md\n' "$HEAD" "$u" > "$WS/$u/.claude/briefs/$u.md"
  mkdir -p "$WS/$u/$(dirname "$2")"; printf '%s\n' "$3" > "$WS/$u/$2"
  git -C "$WS/$u" add "$2"; git -C "$WS/$u" commit -qm "add $2"
  case $EV in
    shot) printf '# e\n\n## Screenshots\n- screenshot: %s\n' "$SHOT" > "$ev" ;;
    none) ;;
    *) printf '# e\n\n## Screenshots\n%s\n' "$EV" > "$ev" ;;
  esac
  # A rulings file the pass has not acknowledged refuses the pass; these cases are not about that refusal.
  [ -z "$RULINGS" ] || (cd "$WS/$u" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json \
    bash "$PASS_SH" --ack-rulings "$u" >/dev/null 2>"$TMP/ack.err") || { echo "FAIL the rulings ack on $u: $(cat "$TMP/ack.err")"; FAIL=$((FAIL+1)); }
  go "$u"
}
# back: main as it was, and the case's inputs cleared.
back() { git -C "$REPO" reset -q --hard "$H0"; rm -f "$REPO"/.claude/briefs/*-main-rulings.md; PLAN="" RULINGS="" EV=shot HEAD='##'; }
refused() { grep -c "^FAILED step 1 preconditions: $1" "$TMP/out"; }
BTN='<Button disabled={true}>Export</Button>' BTN2='<Button disabled={true}>Delete</Button>'
X=web/src/pages/X.tsx

# --- Issue 392: screen evidence ---
EV=none; cu s1 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s1)
check "with the default, a screen diff under web/src with no evidence is refused" "1 1" \
  "$rc $(refused "screen code changed (web/src/pages/A.tsx) and .claude/briefs/s1-evidence.md has no ## Screenshots")"
back

mkdir -p "$REPO/.claude"; printf '{"version":1,"screenPaths":["app/ui/"]}\n' > "$REPO/.claude/commandeck.json"
git -C "$REPO" add .claude/commandeck.json; git -C "$REPO" commit -qm "screenPaths"; H0=$(git -C "$REPO" rev-parse HEAD)
EV=none; cu s2 app/ui/B.tsx '<p>hi</p>'; rc=$(merge s2); r1="$rc $(refused 'screen code changed (app/ui/B.tsx)')"; back
EV=none; cu s2b web/src/pages/C.tsx '<p>hi</p>'; rc=$(merge s2b)
check "a set folder replaces the default" "1 1 0" "$r1 $rc"
back
printf '{"version":1,"screenPaths":[]}\n' > "$REPO/.claude/commandeck.json"; git -C "$REPO" commit -qam "no screens"; H0=$(git -C "$REPO" rev-parse HEAD)
EV=none; cu s3 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s3)
check "with screenPaths empty a screen diff merges unchecked" "0 0" "$rc $(grep -c '^STEP 1 screens' "$TMP/out")"
back
git -C "$REPO" rm -q .claude/commandeck.json; git -C "$REPO" commit -qm "default screenPaths"; H0=$(git -C "$REPO" rev-parse HEAD)

EV=none; cu s4 web/src/lib/x.ts 'export const x = 1;'; rc=$(merge s4)
check "a logic file in screen folders merges with no screens line" "0 0" "$rc $(grep -c '^STEP 1 screens' "$TMP/out")"
back
EV=none; cu s5 web/src/__tests__/y.test.tsx 'it("x", () => {});'; rc=$(merge s5)
check "a test file under screen folders merges" "0 0" "$rc $(grep -c '^STEP 1 screens' "$TMP/out")"
back
EV="- side-by-side: $MOCK | $SHOT"; cu s6 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s6)
check "a side-by-side row whose files exist merges" "0 1" "$rc $(grep -c '^STEP 1 screens: 1 rows$' "$TMP/out")"
back
EV="- screenshot: $TMP/missing.png"; cu s7 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s7)
check "a named missing screenshot is refused" "1 1" "$rc $(refused ".claude/briefs/s7-evidence.md names $TMP/missing.png, which does not exist")"
back
cu s8 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s8)
check "a screenshot row whose file exists merges" "0 1" "$rc $(grep -c '^STEP 1 screens: 1 rows$' "$TMP/out")"
back
EV='- none: no visual change: copy typo in a label'; cu s9 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s9)
check "a no-visual-change row merges and prints its reason" "0 1" "$rc $(grep -c '^STEP 1 screens: no visual change declared: copy typo in a label$' "$TMP/out")"
back
EV='- none: no visual change: '; cu s10 web/src/pages/A.tsx '<p>hi</p>'; rc=$(merge s10)
check "a no-visual-change row with no reason is refused" "1 1" "$rc $(refused 'screen code changed (web/src/pages/A.tsx)')"
back

# --- Issue 398: placeholder UI ---
cu p1 $X "$BTN"$'\n'"$BTN2"; rc=$(merge p1)
check "an unrequested always-disabled control is refused and listed" "1 1 1 1" \
  "$rc $(refused 'unrequested placeholder UI (2)') $(grep -c "$X:1: disabled in $BTN" "$TMP/out") $(grep -c "$X:2: disabled in $BTN2" "$TMP/out")"
back
PLAN="Placeholder: $X | $BTN | its target no longer exists"; cu p2 $X "  $BTN"; rc=$(merge p2)
check "a disabled control the plan names merges" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back
PLAN="Placeholder: $X | $BTN | its target no longer exists"; cu p3 $X "$BTN"$'\n'"$BTN2"; rc=$(merge p3)
check "an approved and an unapproved control in one file: only the unapproved one is refused" "1 1 1 0" \
  "$rc $(refused 'unrequested placeholder UI (1)') $(grep -c "$X:2: disabled in $BTN2" "$TMP/out") $(grep -c "$X:1:" "$TMP/out")"
back
PLAN="Placeholder: $X | $BTN | its target no longer exists"; cu p4 $X "$BTN$BTN2"; rc=$(merge p4)
check "an approved and an unapproved control on one line are refused" "1 1 2" \
  "$rc $(refused 'unrequested placeholder UI (2)') $(grep -o "$X:1: disabled in" "$TMP/out" | wc -l | tr -d ' ')"
back
PLAN="Placeholder: $X | disabled={true} | why"; cu p5 $X "$BTN"; rc=$(merge p5)
check "a bare-substring approval approves nothing" "1 1" "$rc $(refused 'unrequested placeholder UI (1)')"
back
cu p6 $X '<Button disabled={busy}>Export</Button>'; rc=$(merge p6)
check "a dynamic disabled prop merges" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back
cu p7 $X $'const disabled = busy;\nif (disabled) return null;\n<Button disabled={disabled}>Export</Button>'; rc=$(merge p7)
check "a variable named disabled and a dynamic prop merge" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back
# The check reads one line at a time: a tag split over lines is a stated miss (plan Accepted failure mode 10).
cu p8 $X $'<Button\n  disabled\n>Export</Button>'; rc=$(merge p8)
check "a disabled attribute on its own line inside a tag is a stated miss" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back
cu p9 $X '<Button onClick={() => save()} disabled={true}>Export</Button>'; rc=$(merge p9)
check "a disabled control after an arrow-function prop is refused" "1 1 1" \
  "$rc $(refused 'unrequested placeholder UI (1)') $(grep -c "$X:1: disabled in" "$TMP/out")"
back
cu p10 $X '<input title="a > b" disabled />'; rc=$(merge p10)
check "a disabled control after a quoted > is refused" "1 1 1" \
  "$rc $(refused 'unrequested placeholder UI (1)') $(grep -c "$X:1: disabled in" "$TMP/out")"
back
RULINGS="Placeholder: $X | <p>Coming soon</p> | the plan defers this tab"; cu p11 $X '<p>Coming soon</p>'; rc=$(merge p11)
check "placeholder copy main's rulings name merges" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back
cu p12 $X '<p>Coming soon</p>'; rc=$(merge p12)
check "unrequested placeholder copy is refused with the match and the line" "1 1" "$rc $(refused "unrequested placeholder UI (1): $X:1: Coming soon in <p>Coming soon</p>")"
back
PLAN="Placeholder: $X | $BTN | its target no longer exists"; cu p13 $X "$BTN"$'\n'"$BTN"; rc=$(merge p13)
check "two identical added lines need two Placeholder lines" "1 1 1" \
  "$rc $(refused 'unrequested placeholder UI (1)') $(grep -c "$X:2: disabled in" "$TMP/out")"
back
# builder-launch.sh nests the batch two heading levels down, so a launched brief names its plan under #### Plan.
HEAD='####' PLAN="Placeholder: $X | $BTN | its target no longer exists"; cu p14 $X "$BTN"; rc=$(merge p14)
check "a plan named under the launcher's #### Plan heading approves its control" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back
# Only the value line of a multiline disabled={...} changes: a stated miss (plan Accepted failure mode 10).
MULTI=$'<Button\n  disabled={\n    busy\n  }\n>Export</Button>'
mkdir -p "$REPO/${X%/*}"; printf '%s\n' "$MULTI" > "$REPO/$X"; git -C "$REPO" add "$X"; git -C "$REPO" commit -qm "multiline control"
cu p15 $X "${MULTI/busy/true}"; rc=$(merge p15)
check "changing only the value of a multiline disabled attribute to true is a stated miss" "0 0" "$rc $(grep -c 'unrequested placeholder UI' "$TMP/out")"
back

# The check itself: every ordering that once misled a context-tracking scanner (passes 1 to 4, fix rounds 2 and 3, in
# that order). Each line is judged alone, so a line's result never depends on what came before it: a control spelled
# in source text is refused (lines 1-4, 10, 13, 18), a real one is never hidden (17, after pass 4's generic), and a
# tag split over lines is missed (7-8, 25-29). Plan Accepted failure mode 10.
. "$REAL/hooks/lib/screen-code.sh"
ORDER=$(cat <<'TSX'
const preview = "<Button disabled>Export</Button>";
const example = `<button disabled>Export</button>`;
// Example: <Button disabled>Export</Button>
<div>{/* Example: <Button disabled>Export</Button> */}</div>
<p>Don't stop</p>
<Button disabled>Export</Button>
<Button disabled
  ={busy}>Export</Button>
const t = useState<string>("");
const s = "<Button disabled>";
const f = <T,>(x: T) => x;
if (i <length) n = 1 <<x;
const re = /<Button disabled>/;
type F = <U>(u: U) => U;
const q = "</U>";
type G = <U>(x: "</U>") => U;
const view = <Button disabled />;
<script>const h = "<button disabled>";</script>
<input disabled>
<Menu icon={<Button disabled />} />
<A disabled /* c */ ={busy}>x</A>
<A disabled={/* } */ busy}>x</A>
<A /* note */ disabled>x</A>
<A disabled={ /* c */ true }>x</A>
<Button
  disabled={
    true
  }
>Export</Button>
TSX
)
whole=$(always_disabled_lines <<<"$ORDER" | tr '\n' ' ')
alone=$(n=0; while IFS= read -r l; do n=$((n + 1)); always_disabled_lines <<<"$l" | sed "s/.*/$n/"; done <<<"$ORDER" | tr '\n' ' ')
check "scanner: every line is judged alone, whatever came before it" \
  "1 2 3 4 6 10 13 17 18 19 20 21 23 |1 2 3 4 6 10 13 17 18 19 20 21 23 " "$whole|$alone"

# --- Issue 396: step 5 closes the Builder's task before the panes close; a refused close changes neither the merge's
# exit code nor its cleanup. A stub unit-close.sh in the copied scripts logs into the orca-ide call log. ---
cp "$REAL/scripts/unit-close.sh" "$TMP/unit-close.real"
printf '#!/usr/bin/env bash\necho "unit-close $*" >> "%s/orca-calls"\n[ ! -e "%s/close-refused" ] || { echo "STEP 5 task NOT closed: stub"; exit 1; }\n' "$TMP" "$TMP" > "$REAL/scripts/unit-close.sh"
: > "$TMP/orca-calls"; cu c1 web/src/lib/c1.ts 'export const c = 1;'; rc=$(merge c1)
check "a merge closes its Builder task completed" "0 1 unit-close c1 merged" \
  "$rc $(grep -c '^unit-close c1 merged$' "$TMP/orca-calls") $(grep -E '^unit-close|^terminal close' "$TMP/orca-calls" | head -1)"
back
touch "$TMP/close-refused"; : > "$TMP/orca-calls"; cu c2 web/src/lib/c2.ts 'export const c = 2;'; rc=$(merge c2)
check "a refused task close leaves the merge's exit code and cleanup" "0 1 1" \
  "$rc $(grep -c '^STEP 5 task NOT closed: stub' "$TMP/out") $(grep -c 'terminal close' "$TMP/orca-calls" | awk '{ print ($1 > 0) }')"
rm -f "$TMP/close-refused"; cp "$TMP/unit-close.real" "$REAL/scripts/unit-close.sh"
back

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

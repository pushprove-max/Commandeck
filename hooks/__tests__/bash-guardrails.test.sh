#!/usr/bin/env bash
# timeout: 300 -- about 193s run alone on the Mac (2026-09-27)
# Self-test for bash-guardrails.sh. Run directly.
set -u
export COMMANDECK_REVIEWER=0 COMMANDECK_HOOK_TIER=strict

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0

# The file runs itself once per part, side by side, and prints the parts in
# order: a hook call costs about 0.2 s and there are some 900. Every
# line runs in every part, so each part has all fixtures and helpers; outside
# its own part a run has `true` for the hook and check records nothing.
# One part alone: GUARDRAILS_TEST_PART=<n> in front. Five parts, not four:
# of four, two ran 77 and 79 s side by side while the shortest ran 34 s.
PARTS=5
if [ -z "${GUARDRAILS_TEST_PART:-}" ]; then
  OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
  for P in $(seq "$PARTS"); do GUARDRAILS_TEST_PART=$P bash "$0" > "$OUT/$P" 2>&1 & done
  wait
  for P in $(seq "$PARTS"); do
    # A part that died before its count, or ran no case, is a failure, never a shorter list.
    if [[ $(tail -1 "$OUT/$P") =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]] && grep -qE '^(ok  |FAIL) ' "$OUT/$P"; then
      PASS=$((PASS+BASH_REMATCH[1])) FAIL=$((FAIL+BASH_REMATCH[2]))
      sed '$d' "$OUT/$P" | sed '${/^$/d;}'
    else
      cat "$OUT/$P"; echo "FAIL part $P of $PARTS did not finish"; FAIL=$((FAIL+1))
    fi
  done
  echo
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]; exit
fi
case "$GUARDRAILS_TEST_PART" in [1-$PARTS]) ;; *) echo "FAIL no such part: $GUARDRAILS_TEST_PART (parts: 1 to $PARTS)" >&2; exit 2 ;; esac
REAL_HOOK=$HOOK
part() { if [ "$1" = "$GUARDRAILS_TEST_PART" ]; then ON=1 HOOK=$REAL_HOOK; else ON=0 HOOK=true; fi; }
part 1

# The main-only guards read the SESSION's checkout, and a linked worktree turns
# them off. Every default case runs from a disposable MAIN repository, so a run
# from a worker worktree still exercises them instead of silently passing.
MAIN_TMP=$(mktemp -d)
git -C "$MAIN_TMP" init -q
printf '{}\n' > "$MAIN_TMP/package.json"
trap 'rm -rf "$MAIN_TMP"' EXIT

run_hook() { ( cd "$MAIN_TMP" && echo "$1" | "$HOOK" >/dev/null 2>&1; echo $? ); }
check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# Outside its own part a run builds no payload: every part paid a jq per case for nothing.
json() { [ "$ON" = 1 ] || return 0; jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }
# A refusal these guards keep must hand back a concrete command. Take its
# `Try:` line and replay it in the same seat: it has to pass, or the advice is
# a placeholder or something another guard blocks.
check_try() { # label, command, [seat dir]
  local DIR=${3:-$MAIN_TMP} OUT TRY
  OUT=$(cd "$DIR" && json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(cd "$DIR" && json "$TRY" | "$HOOK" >/dev/null 2>&1; echo $?)"
}

# --- heap cap on node's test runner -------
check "bare node --test blocks" 2 \
  "$(run_hook "$(json 'node --test src/x.test.ts')")"
check "node --require ts-node/register --test blocks" 2 \
  "$(run_hook "$(json 'node --require ts-node/register --test src/x.test.ts')")"
# V8 reads the flag with underscores and with a space before the number too:
# the last one of any spelling is the heap node runs with.
check "a later underscore spelling above the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max_old_space_size=8192 --test src/x.test.ts')")"
check "a later space-separated value above the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max-old-space-size 8192 --test src/x.test.ts')")"
check "the underscore spelling at the cap passes" 0 \
  "$(run_hook "$(json 'node --max_old_space_size=4096 --test src/x.test.ts')")"
check "cap ABOVE 4096 still blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=8192 --test src/x.test.ts')")"
check "npx tsx --test blocks" 2 \
  "$(run_hook "$(json 'npx tsx --test src/x.test.ts')")"
check "node --test after a && still blocks" 2 \
  "$(run_hook "$(json 'npm run build && node --test src/x.test.ts')")"

check "npm run test:unit passes (script carries the cap)" 0 \
  "$(run_hook "$(json 'npm run test:unit')")"
check "npm test passes" 0 \
  "$(run_hook "$(json 'npm test')")"
check "capped node --test passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test src/x.test.ts')")"
check "capped node --test with ts-node passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test --require ts-node/register src/x.test.ts')")"
check "a lower cap passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=2048 --test src/x.test.ts')")"
check "ordinary node script passes" 0 \
  "$(run_hook "$(json 'node scripts/thing.js')")"
check "companion --test-concurrency flag alone is not the runner switch" 0 \
  "$(run_hook "$(json 'node --test-concurrency=4 scripts/thing.js')")"

# --- per-segment cap: one segment's flag must not vouch for another ---------
check "capped segment does not vouch for an uncapped one" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts && node --test b.test.ts')")"
check "uncapped segment after a semicolon blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts; node --test b.test.ts')")"
check "both segments capped passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts && node --max-old-space-size=4096 --test b.test.ts')")"
check "npm segment is skipped, node args and all" 0 \
  "$(run_hook "$(json 'npm run test:unit -- node --test x.test.ts')")"
check "a single & is a segment boundary too" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts & node --test b.test.ts')")"
check "a larger flag after the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max-old-space-size=8192 --test x.test.ts')")"
# No heap flag above the cap, in either spelling, wherever it sits. The
# guard used to read the hyphen spelling only and trust the last one, so the
# underscore spelling after the cap ran node at 8 GB. Which flag node honours is
# no longer the guard's question: a larger one has no reason to be there.
check "a larger flag before the cap blocks too" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=8192 --max-old-space-size=4096 --test x.test.ts')")"
check "the underscore spelling after the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max_old_space_size=8192 --test x.test.ts')")"
check "the underscore spelling after the runner switch blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test x.test.ts --max_old_space_size=8192')")"
check "a mixed spelling blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max_old-space_size=8192 --test x.test.ts')")"
check "a larger flag written with a space blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max-old-space-size 8192 --test x.test.ts')")"
check "a larger flag in NODE_OPTIONS beside the cap blocks" 2 \
  "$(run_hook "$(json 'NODE_OPTIONS=--max_old_space_size=8192 node --max-old-space-size=4096 --test x.test.ts')")"
check "the underscore spelling alone, above the cap, blocks" 2 \
  "$(run_hook "$(json 'node --max_old_space_size=8192 --test x.test.ts')")"
check "the underscore spelling at the cap is the cap" 0 \
  "$(run_hook "$(json 'node --max_old_space_size=4096 --test x.test.ts')")"
check "the cap in NODE_OPTIONS still passes" 0 \
  "$(run_hook "$(json 'NODE_OPTIONS=--max-old-space-size=4096 node --test x.test.ts')")"
check "the cap twice, one in each spelling, passes" 0 \
  "$(run_hook "$(json 'NODE_OPTIONS=--max-old-space-size=4096 node --max_old_space_size=2048 --test x.test.ts')")"
# The same miss as git-safety.sh's: a quoted word is still the word node gets.
check "a quoted runner switch is still the runner" 2 \
  "$(run_hook "$(json 'node "--test" x.test.ts')")"
check "a quoted node is still node" 2 \
  "$(run_hook "$(json '"node" --test x.test.ts')")"
check "a quoted larger flag beside the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 "--max_old_space_size=8192" --test x.test.ts')")"
check "a quoted cap is the cap" 0 \
  "$(run_hook "$(json 'node "--max-old-space-size=4096" --test x.test.ts')")"
check "a quoted cap in NODE_OPTIONS is the cap" 0 \
  "$(run_hook "$(json 'NODE_OPTIONS="--max-old-space-size=4096" node --test x.test.ts')")"
check "a larger flag in another segment does not block a capped run" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=8192 build.js && node --max-old-space-size=4096 --test x.test.ts')")"

# --- prefixes and quoting: what is not actually a node invocation ------------
check "VAR=value before npm still reads as npm" 0 \
  "$(run_hook "$(json 'CI=1 npm run test:unit -- node --test x.test.ts')")"
check "env before npm still reads as npm" 0 \
  "$(run_hook "$(json 'env CI=1 npm run test:unit -- node --test x.test.ts')")"
check "a VAR=value prefix does NOT excuse a real node --test" 2 \
  "$(run_hook "$(json 'CI=1 node --test x.test.ts')")"
check "the pattern inside single quotes is a search, not a command" 0 \
  "$(run_hook "$(json "rg 'node --test src/x.test.ts' .claude")")"
check "the pattern inside double quotes passes too" 0 \
  "$(run_hook "$(json 'grep -rn "node --test" docs/')")"
check "a real invocation BESIDE a quoted mention still blocks" 2 \
  "$(run_hook "$(json "rg 'node --test' .claude && node --test x.test.ts")")"
# the strip ran line by line, so a quote or heredoc spanning lines kept
# its prose and a commit message naming the runner blocked.
check "a heredoc commit message naming node --test passes" 0 \
  "$(run_hook "$(json $'git commit -m "$(cat <<\'EOF\'\nfix: the suite ran node --test without a cap\nEOF\n)"')")"
check "a two-line quoted message naming node --test passes" 0 \
  "$(run_hook "$(json $'git commit -m "first\nnode --test x.test.ts"')")"
check "a real node --test after a heredoc still blocks" 2 \
  "$(run_hook "$(json $'cat <<EOF\nnode --test prose\nEOF\nnode --test x.test.ts')")"
check "an empty quote inside --test does not dodge the prefilter" 2 \
  "$(run_hook "$(json "node --te''st x.test.ts")")"
check "the heap check prints no grep warning" "" \
  "$(cd "$MAIN_TMP" && json 'node --max-old-space-size=4096 --test x.test.ts' | "$HOOK" 2>&1 >/dev/null)"

# --- the tool-steering rules are gone ---------------------------------------
# The hook told Claude to use Read instead of cat and Glob instead of find.
# That cost a fork on every Bash call to restate a preference no incident
# traces to, and Codex has neither tool, so the rule already carried an
# AGENT_KIND branch to switch itself off for half its callers.
READ_TMP=$(mktemp -d)
printf 'one line\n' >"$READ_TMP/small.md"
head -c 40000 /dev/zero | tr '\0' 'x' >"$READ_TMP/big.md"

check "cat for reading passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/small.md")")"
check "head for reading passes" 0 \
  "$(run_hook "$(json 'head -20 package.json')")"
check "cat for reading is SILENT" "" \
  "$(cd "$MAIN_TMP" && echo "$(json "cat $READ_TMP/small.md")" | "$HOOK" 2>&1)"
check "find for discovery passes" 0 \
  "$(run_hook "$(json 'find src -name "*.ts"')")"
check "find for discovery is SILENT" "" \
  "$(cd "$MAIN_TMP" && echo "$(json 'find src -name "*.ts"')" | "$HOOK" 2>&1)"

# --- the read cap applies to every file, not just TypeScript ----------------
# Widened 2026-09-15: the four files Sol printed most in a day were two
# SKILL.md, a brief and a shell script, and the source-only pattern this rule
# used to carry exempted all four.
check_try "cat of a file over the cap blocks, whatever its type" \
  "cat $READ_TMP/big.md"
check_try "nl of a file over the cap blocks" \
  "nl -ba $READ_TMP/big.md"
check "cat of a file that does not exist passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/absent.md")")"
check "a redirect is a write, not a read, so it passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/big.md > $READ_TMP/copy.md")")"
check "a heredoc write passes" 0 \
  "$(run_hook "$(json "cat > $READ_TMP/big.md <<'EOF'")")"
# A note's text is data: a here-document that cat or tee reads, alone on its
# line, with nothing after its end word. Any other here-document is read as
# commands: a shell may be fed it, or a later line may run the file.
check "a note written by cat that names a pathless search passes" 0 \
  "$(run_hook "$(json "cat > /tmp/note.md <<'EOF'
rg -n foo
EOF")")"
check "a note appended by cat, tab-indented, that a command follows is read as a search" 2 \
  "$(run_hook "$(json "cat >> /tmp/note.md <<-'EOF'
	rg foo \$X
	EOF
ls")")"
check "a note with no quoted end word that names a pathless search passes" 0 \
  "$(run_hook "$(json "cat > /tmp/note.md <<EOF
rg -n foo
EOF")")"
check "a note written by tee that names a pathless search passes" 0 \
  "$(run_hook "$(json "tee /tmp/note.md <<'EOF' >/dev/null
rg -n foo
EOF")")"
check "a pathless search after the note ends still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/note.md <<'EOF'
note
EOF
rg -n foo")")"
check "a pathless search after two notes still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/a.md <<'A'
rg x
A
cat > /tmp/b.md <<'B'
rg y
B
rg -n foo")")"
# Under an end word with no quote bash runs a substitution in the body.
for NOTE_CMD in "cat <<EOF
\$(
rg -n foo
)
EOF" "tee /tmp/n.md <<EOF
\$(
rg -n foo
)
EOF" "cat > /tmp/n.md <<-EOF
	\`
	rg -n foo
	\`
	EOF" "cat <<123
\$(
rg -n foo
)
123" "cat > /tmp/n.md <<EOF
x \${Y:-\$(
rg -n foo
)}
EOF"; do
  check "a pathless search a note with no quoted end word runs still blocks: $NOTE_CMD" 2 "$(run_hook "$(json "$NOTE_CMD")")"
done
check "the same substitution under a quoted end word runs nothing and passes" 0 \
  "$(run_hook "$(json "cat <<'EOF'
\$(
rg -n foo
)
EOF")")"
part 2
# The search rule looks inside `$( )` and backticks.
g() { check "substitution: $1" "$2" "$(run_hook "$(json "$3")")"; }
# The search rule reads the words the shell would run, not the command's raw text: a name the shell puts together
# from quoted pieces is the same program.
g "a search whose name is written in quoted pieces is still a search" 2 "r''g -n foo"
g "the same for grep, in a substitution" 2 'x=$(g""rep -rn foo)'
g "the same with a backslash in the name" 2 'r\g -n foo'
g "stated limit: a here-document written to a shell through a process substitution is read as a note" 0 "cat > >(bash) <<'EOF'
rg -n foo
EOF"
g "a pathless search in an assignment's substitution is refused" 2 'X=$(rg -n foo)'
g "a pathless search on a line of an unquoted note is refused" 2 'cat <<EOF
$(rg -n foo)
EOF'
g "a note with a dated line that names a search passes" 0 'cat > /tmp/note.md <<EOF
Recorded at $(date)
rg -n foo
EOF'
g "a pathless search in a substitution used as an argument is refused" 2 'echo $(rg -n foo)'
g "a pathless search in a substitution that is the whole command is refused" 2 '$(rg -n foo)'
g "a pathless search in a substitution inside a double-quoted string is refused" 2 'echo "hits: $(rg -n foo)"'
g "a pathless search in backticks is refused" 2 'X=`rg -n foo`'
g "a pathless search in backticks inside a double-quoted string is refused" 2 'echo "hits: `rg -n foo`"'
g "a pathless search in backticks inside an unquoted note is refused" 2 'cat <<EOF
`rg -n foo`
EOF'
g "a pathless search in a substitution mid-line in an unquoted note is refused" 2 'cat > /tmp/n.md <<EOF
hits: $(rg -n foo) end
EOF'
g "an unquoted note that names a search mid-line passes" 0 'cat > /tmp/n.md <<EOF
run rg -n foo to look
EOF'
g "an apostrophe in an unquoted note does not hide a search after it" 2 "cat > /tmp/n.md <<EOF
it's a note
EOF
rg -n foo"
g "an apostrophe in a quoted note does not hide a search after it" 2 "cat > /tmp/n.md <<'EOF'
it's a note
EOF
rg -n foo"
g "an apostrophe in an unquoted note does not hide a substitution after it" 2 "cat > /tmp/n.md <<EOF
it's \$(rg -n foo)
EOF
ls"
g "a bounded search in a substitution passes" 0 'X=$(rg -n foo src)'
g "plain substitutions pass" 0 'echo $(date) $(git rev-parse HEAD) `whoami`'
g "a quoted note with plain text passes" 0 "cat > /tmp/n.md <<'EOF'
a note
EOF"
g "a substitution spelled inside single quotes passes" 0 "echo '\$(rg -n foo)' '\`rg -n foo\`'"
g "an escaped substitution passes" 0 'echo \$(rg -n foo) "\$(rg -n foo)"'
g "an escaped substitution in an unquoted note passes" 0 'cat > /tmp/n.md <<EOF
write \$(rg -n foo) and \`rg -n foo\`
EOF'
# One level of nesting, each form inside another.
g "a substitution in a double-quoted string in a substitution is refused" 2 'X=$(echo "a $(rg -n foo)")'
g "backticks in a substitution are refused" 2 'X=$(echo `rg -n foo`)'
g "a substitution in a substitution in an unquoted note is refused" 2 'cat <<EOF
$(echo "$(rg -n foo)")
EOF'
g "a substitution in a default value is refused" 2 'echo "${Y:-$(rg -n foo)}"'
g "a search over the checkout root in a substitution is refused" 2 'X=$(rg -n foo .)'
g "a recursive grep with no path in a substitution is refused" 2 'X=$(grep -rn foo)'
g "a grep of one file in a substitution passes" 0 'X=$(grep -n foo /tmp/x.log)'
# The substitution is judged as its own command line, where it stands.
g "a bounded search piped on inside a substitution passes" 0 'N=$(rg -c foo src | wc -l)'
g "a search reading a pipe inside a substitution passes" 0 'N=$(cat /tmp/x.log | rg foo)'
g "a search reading a pipe beside a substitution passes" 0 'echo "$(date)" | rg foo'
g "a search with its pattern from a substitution and a bounded path passes" 0 'rg -n -e "$(cat /tmp/pat)" src'
g "a search with its pattern from a substitution and no path is refused" 2 'rg -n -e "$(cat /tmp/pat)"'
g "a path in a variable the command sets is followed into a substitution" 0 'D=src; X=$(rg -n foo "$D")'
g "a cd before a substitution is followed" 0 "cd $READ_TMP && X=\$(rg -n foo .)"
g "a cd after a substitution does not bound it" 2 "X=\$(rg -n foo .); cd $READ_TMP"
# A substitution runs in its own shell: its cd and its assignments end with it.
g "a cd inside a substitution does not bound a search after it" 2 "X=\$(cd $READ_TMP); rg -n foo ."
g "a cd inside backticks does not bound a search after it" 2 "X=\`cd $READ_TMP\`; rg -n foo ."
g "a cd inside a quoted substitution does not bound a search after it" 2 "echo \"\$(cd $READ_TMP && rg -n foo .)\"; rg -n foo ."
g "an assignment inside a substitution does not rename a path after it" 2 'D=.; X=$(D=src); rg -n foo "$D"'
g "a cd inside a substitution bounds the search inside it" 0 "X=\$(cd $READ_TMP && rg -n foo .)"
g "an assignment inside a substitution names the path inside it" 0 'X=$(D=src; rg -n foo "$D")'
g "a cd before a substitution still bounds the search after it" 0 "cd $READ_TMP && X=\$(rg -n foo .) && rg -n bar ."
# One level of nesting: the inner one runs after the outer one's own commands before it, in the outer one's shell.
g "a nested search is judged after the outer substitution's assignment" 2 'D=src; X=$(D=.; echo "$(rg -n foo "$D")")'
g "a nested search in backticks is judged after the outer assignment" 2 'D=src; X=$(D=.; echo `rg -n foo "$D"`)'
g "a nested search in a default value is judged after the outer assignment" 2 'D=src; X=$(D=.; echo "${Y:-$(rg -n foo "$D")}")'
g "a nested search is bounded by the outer substitution's assignment" 0 'D=.; X=$(D=src; echo "$(rg -n foo "$D")")'
g "a nested search is judged after the outer substitution's cd" 0 "X=\$(cd $READ_TMP; echo \"\$(rg -n foo .)\")"
g "a cd in a nested substitution ends with it, inside the outer one" 2 "X=\$(echo \"\$(cd $READ_TMP)\"; rg -n foo .)"
g "an assignment in a nested substitution ends with it, inside the outer one" 2 'X=$(D=.; echo "$(D=src)"; rg -n foo "$D")'
g "the outer substitution's cd ends with it after a nested one" 2 "X=\$(cd $READ_TMP; echo \"\$(date)\"); rg -n foo ."
g "a bounded nested search still passes" 0 'X=$(echo "$(rg -n foo src)")'
# The shape the plugin's own issue reported: the outer substitution goes back to the root, and the inner search runs there.
g "a nested search after the outer substitution's cd back to the checkout root is refused" 2 "cd $READ_TMP; X=\$(cd $MAIN_TMP; echo \"\$(rg -n foo .)\")"
# Stated limits, each pinned as today's behaviour: the shell does not move, the guard thinks it did.
g "stated limit: a cd inside a pipeline is still followed" 0 "cd $READ_TMP | true; rg -n foo ."
g "stated limit: a cd in the background is still followed" 0 "cd $READ_TMP & rg -n foo ."
g "stated limit: a cd under a condition that does not run is still followed" 0 "false && cd $READ_TMP; rg -n foo ."
g "an apostrophe in a comment does not hide a substitution after it" 2 "echo hi # it's
X=\$(rg -n foo)"
g "a substitution after a \$'...' string with an escaped quote is refused" 2 "echo \$'it\\'s'; X=\$(rg -n foo)"
g "a substitution in a comment passes" 0 'echo hi # $(rg -n foo)'
g "plain arithmetic beside a substitution passes" 0 'echo $((1 + 2)) $((1<<2)) $(date)'
# The `)` that closes a subshell is not part of the path it stands against.
g "a root search in a subshell, the bracket against the path, is refused" 2 '(rg -n foo /)'
g "a home search in a subshell is refused" 2 '(grep -r foo ~)'
g "a search over the checkout root in a subshell is refused" 2 '(rg -n foo .)'
g "a parent search in a subshell inside a subshell is refused" 2 '( (rg -n foo ..))'
g "a \$HOME search in a subshell is refused" 2 '(rg -n foo $HOME)'
g "a root search after a cd in a subshell is refused" 2 "(cd $READ_TMP && rg -n foo /)"
g "a bounded search in a subshell passes" 0 '(rg -n foo hooks)'
g "a bounded search after a cd in a subshell passes" 0 "(cd $READ_TMP && rg -n foo .)"
# What is on disk does not decide how the shell reads the bracket: a file named `.)` in the checkout
# once made `(rg -n foo .)` a search of that file, and the whole checkout was searched.
git init -q "$READ_TMP/co"; : > "$READ_TMP/co/.)"; mkdir "$READ_TMP/co/in"; : > "$READ_TMP/co/in/x)"
g "a checkout search in a subshell is refused whatever file is named like its last word" 2 "(cd $READ_TMP/co && rg -n foo .)"
g "a bounded path that ends in a bracket still passes" 0 "cd $READ_TMP/co && rg -n foo in/x)"
g "a search after an arithmetic shift is still refused" 2 'echo $((1<<2))
rg -n foo'
g "a search after a quoted here-document opener is still refused" 2 'echo "x; cat <<EOF"
rg -n foo'
# What is not a note is read as commands, as before.
g "a note that a command follows is read as commands" 2 'cat > /tmp/note.md <<EOF
Recorded at $(date)
rg -n foo
EOF
ls'
g "a note with a harmless substitution that a command follows passes" 0 'cat > /tmp/note.md <<EOF
Recorded at $(date)
EOF
ls'
g "a here-document with a command after it on its line is read as commands" 2 'cat > /tmp/n.sh <<EOF && bash /tmp/n.sh
rg -n foo
EOF'
g "a here-document a substitution's cat prints is read as commands" 2 'eval "$(cat <<EOF
rg -n foo
EOF
)"'
g "a here-document fed to a shell with no quoted end word is read as commands" 2 'bash <<EOF
rg -n foo
EOF'
# A search after a note is judged, whatever the note's end word.
for NOTE_CMD in "cat <<'END NOTE'
note
END NOTE
rg -n foo" "cat > /tmp/n.md <<'END NOTE'
note
END NOTE
rg -n foo" "cat <<E'OF'
note
EOF
rg -n foo" "cat <<'E'OF
note
EOF
rg -n foo" "cat <<\"E\"\"OF\"
note
EOF
rg -n foo" "cat <<E\\OF
note
EOF
rg -n foo" "cat <<EOF2
note
EOF2
rg -n foo" "cat <<'EOF'
note
EOF
cat <<'EOF'
note
EOF
rg -n foo"; do
  check "a pathless search after a note still blocks: $NOTE_CMD" 2 "$(run_hook "$(json "$NOTE_CMD")")"
done
# A here-document's end word is one plain word or the command is refused: no
# rule then has to read an odd one. Refused whatever follows, with or without
# a command after the note, and for the search rule and the in-place write
# rule alike.
ODD_ENDS=("<<'END NOTE'" "<<E'OF'" "<<'E'OF" '<<"E""OF"' "<<E\\OF" "<<'END'\\ NOTE" '<<"E\"OF"' '<<$TAG' '<<EOF#x' '<<~EOF' '<<' '<<-' "<<''" '<<EOF<<"A B"')
for E in "${ODD_ENDS[@]}"; do
  check "an end word that is not plain is refused: $E" 2 "$(run_hook "$(json "cat $E
note")")"
  check "and so is a search after such a note: $E" 2 "$(run_hook "$(json "cat $E
It's a note
EOF
rg -n foo")")"
  check "and an in-place source write after such a note: $E" 2 "$(run_hook "$(json "cat $E
note
EOF
sed -i s/a/b/ src/index.ts")")"
done
END_REFUSAL=$(json "cat <<'END NOTE'
note
END NOTE" | (cd "$MAIN_TMP" && "$HOOK" 2>&1 >/dev/null))
check "the refusal is one line that names the end word it saw and a plain one to use" "1 1 1" \
  "$(wc -l <<<"$END_REFUSAL" | tr -d ' ') $(grep -c "<<'END NOTE'" <<<"$END_REFUSAL") $(grep -c 'such as EOF' <<<"$END_REFUSAL")"
for E in "<<EOF" "<<'EOF'" '<<"EOF"' "<<\\EOF" "<< EOF" "<<-EOF" "<<-'EOF'" "<<EOF2" "<<E_O.F-1" "<<EOF >/tmp/n.md" "<<EOF;"; do
  check "a plain end word passes: $E" 0 "$(run_hook "$(json "cat $E
note
EOF")")"
done
check "a here-string is not a here-document and passes" 0 "$(run_hook "$(json "cat <<<'a note'; cat <<< \"\$X\"")")"
check "a shift in arithmetic passes" 0 "$(run_hook "$(json 'echo $((1<<2)) $((A << 3))')")"
check "a shift by a bracketed amount passes" 0 "$(run_hook "$(json 'echo $((1 << (2 + 1))) $(( (A+1) << B ))')")"
# Only a `<<` that bash would read as an operator is judged: one inside quotes,
# a comment or a plain note's text opens nothing.
for C in "echo '<<'" "node -e \"console.log('<<EOF')\"" "echo \"use <<'END NOTE' never\"" "echo hi # <<'A B'" "cat <<'EOF'
never write <<'END NOTE' or <<E'OF'
EOF"; do
  check "a << that is only text passes: $C" 0 "$(run_hook "$(json "$C")")"
done
check "an odd end word beside a quoted << is still refused" 2 "$(run_hook "$(json "echo '<<EOF'; cat <<'END NOTE'
note
END NOTE")")"
check "an odd end word after arithmetic is still refused" 2 "$(run_hook "$(json "echo \$((1 << 2)); cat <<'END NOTE'
note
END NOTE")")"
# The reader does not know `$'...'`, where `\'` does not end the string; with
# one in the command every `<<` in the text is judged as written.
check "an odd end word after a \$'...' string with an escaped quote is still refused" 2 "$(run_hook "$(json "echo \$'a\\'b'; cat <<'END NOTE'
note
END NOTE")")"
check "a plain end word after a \$'...' string passes" 0 "$(run_hook "$(json "echo \$'a\\'b'; cat <<'EOF'
note
EOF")")"
# Nothing may sit above the check that lets a command leave the hook unread.
check "the end-word check comes before every exit but the empty-command one and the tier gate" 1 \
  "$(awk '/^\[ -z "\$CMD" \] && exit 0$/ || /pp_strict/ { next } /end word is not plain/ { found = 1 } /exit 0/ && !seen { print (found ? 1 : 0); seen = 1 }' \
    "$REAL_HOOK")"
check "a note with a quote mark and nothing after it passes" 0 \
  "$(run_hook "$(json "cat <<'EOF' | tee /tmp/n.md
It's a note
EOF")")"
check "a pathless search in a note that a later line runs still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/n.sh <<'EOF'
rg -n foo
EOF
bash /tmp/n.sh")")"
check "a pathless search in a note that a later line sources still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/n.sh <<'EOF'
rg -n foo
EOF
. /tmp/n.sh")")"
check "a pathless search in a here-document fed to a shell still blocks" 2 \
  "$(run_hook "$(json "bash <<'EOF'
rg -n foo
EOF")")"
check "a pathless search in a here-document cat pipes into a shell still blocks" 2 \
  "$(run_hook "$(json "cat <<'EOF' | bash
rg -n foo
EOF")")"
check "a pathless search in a here-document a subshell's cat prints still blocks" 2 \
  "$(run_hook "$(json "(cat <<'EOF'
rg -n foo
EOF
) | bash")")"
check_try "sed range over the cap blocks on a markdown file" \
  "sed -n '1,400p' $READ_TMP/big.md"
check "sed range under the cap passes" 0 \
  "$(run_hook "$(json "sed -n '1,120p' $READ_TMP/big.md")")"
check_try "head over the cap blocks on any file" \
  "head -400 $READ_TMP/big.md"
check "tail -n 40 of a log passes" 0 \
  "$(run_hook "$(json "tail -n 40 $READ_TMP/big.md")")"
# The file is the one the command reads, so its own `cd` is followed.
# Looked up from the starting folder, `cd <dir> && cat big.md` found no file
# and printed all of it.
mkdir -p "$READ_TMP/sub/briefs-like"; cp "$READ_TMP/big.md" "$READ_TMP/sub/deep.md"; echo small > "$READ_TMP/sub/small.md"
check_try "cat of a big file after a cd into its folder blocks" "cd $READ_TMP && cat big.md"
check_try "and after a cd on an earlier line" "$(printf 'cd %s\ncat big.md' "$READ_TMP")"
check_try "and after two cds, the second relative" "cd $READ_TMP && cd sub && cat deep.md"
check_try "and in a subshell" "(cd $READ_TMP/sub && nl deep.md)"
check_try "a subshell with no cd blocks too" "(cat $READ_TMP/big.md)"
check_try "and with pushd" "pushd $READ_TMP/sub; cat deep.md"
check_try "and through .. from a deeper folder" "cd $READ_TMP/sub/briefs-like && cat ../deep.md"
check_try "and with the folder in a variable the command sets" "D=$READ_TMP/sub; cd \"\$D\" && cat deep.md"
check "a small file after a cd passes" 0 "$(run_hook "$(json "cd $READ_TMP/sub && cat small.md")")"
# Which cd is still in force depends on subshells, `||` and exit codes, and this
# hook does not follow them: a file is sized in every folder the command could
# be in, the starting one and each cd target. Following the last cd let a big
# read through after a subshell had closed.
in_read_tmp() { (cd "$READ_TMP" && json "$1" | "$HOOK" >/dev/null 2>&1; echo $?); }
check "a big file read after a subshell's cd has ended blocks" 2 "$(in_read_tmp "(cd sub && cat small.md); cat big.md")"
check "and after a cd that an || skipped" 2 "$(in_read_tmp "true || cd sub; cat big.md")"
check "and after a cd that failed mid-chain" 2 "$(in_read_tmp "cd sub && false; cd ..; cat big.md")"
check "so a name that is big in the starting folder blocks after a cd away too" 2 "$(in_read_tmp "cd sub && cat big.md")"
check "a name that is small in every folder the command names passes" 0 "$(in_read_tmp "(cd sub && cat small.md); cat sub/small.md")"
check "a cd into a folder that is not there leaves the read where it was" 2 \
  "$(cd "$READ_TMP" && json "cd nowhere; cat big.md" | "$HOOK" >/dev/null 2>&1; echo $?)"
check "an absolute path is read as written, whatever the cd" 2 "$(run_hook "$(json "cd /tmp && cat $READ_TMP/big.md")")"
check "head -c is a byte read, not a line read, and passes" 0 \
  "$(run_hook "$(json "head -c 8000 $READ_TMP/big.md")")"

# Every spelling of a line count is the same read. Only `-N` and `-nN`
# were parsed, so `head -n 400` and `--lines=400` read straight past the cap,
# and a sed range is inclusive, so `1,151p` printed 151 lines and passed.
for T in head tail; do
  for SPELL in -%s -n%s '-n %s' --lines=%s '--lines %s'; do
    for N in 151 200 400; do
      C=$(printf "$T $SPELL" "$N")
      check "$C blocks" 2 "$(run_hook "$(json "$C $READ_TMP/big.md")")"
    done
    for N in 150 40; do
      C=$(printf "$T $SPELL" "$N")
      check "$C passes" 0 "$(run_hook "$(json "$C $READ_TMP/big.md")")"
    done
  done
done
check_try "head -n over the cap hands back a read that passes" \
  "head -n 400 $READ_TMP/big.md"
check_try "tail --lines over the cap hands back a read that passes" \
  "tail --lines 200 $READ_TMP/big.md"
check "a count written after the file still blocks" 2 \
  "$(run_hook "$(json "head $READ_TMP/big.md -n 400")")"
check "a flag cluster ending in n takes the count" 2 \
  "$(run_hook "$(json "tail -qn 400 $READ_TMP/big.md")")"
check "the last count wins: over the cap then under passes" 0 \
  "$(run_hook "$(json "head -n 400 -n 100 $READ_TMP/big.md")")"
check "the last count wins: under the cap then over blocks" 2 \
  "$(run_hook "$(json "head -n 100 --lines=400 $READ_TMP/big.md")")"
check "a piped count over the cap blocks" 2 \
  "$(run_hook "$(json 'git log --oneline | head -n 151')")"
check "a piped count under the cap passes" 0 \
  "$(run_hook "$(json 'git log --oneline | head -n 20')")"
# A byte count is not a line count, however large its number.
for C in 'head -c 400' 'head -c400' 'head --bytes=400' 'head --bytes 400' 'tail -c 400'; do
  check "$C is a byte read and passes" 0 "$(run_hook "$(json "$C $READ_TMP/big.md")")"
done
check "a line count over the cap beside a byte count still blocks" 2 \
  "$(run_hook "$(json "head -c 400 -n 151 $READ_TMP/big.md")")"
check "an inclusive 150-line sed range passes" 0 \
  "$(run_hook "$(json "sed -n '1,150p' $READ_TMP/big.md")")"
check "a 150-line sed window that does not start at 1 passes" 0 \
  "$(run_hook "$(json "sed -n '101,250p' $READ_TMP/big.md")")"
check_try "a 151-line sed range blocks" \
  "sed -n '1,151p' $READ_TMP/big.md"
check_try "a shifted 151-line sed range blocks" \
  "sed -n '101,251p' $READ_TMP/big.md"
check "the sed refusal hands back exactly 150 lines from the same start" \
  "sed -n '101,250p' '$READ_TMP/big.md'" \
  "$(cd "$MAIN_TMP" && json "sed -n '101,400p' $READ_TMP/big.md" | "$HOOK" 2>&1 >/dev/null | sed -n 's/^Try: //p' | head -1)"

# ANSWER THE ESCALATION. One seat met 33 read-cap blocks in a day by
# asking for the next size up each time. Every read-cap refusal has to say that
# a bigger number is not on the menu, or the refusal reads as a negotiation.
for ESC in "cat $READ_TMP/big.md" "sed -n '1,400p' $READ_TMP/big.md" "head -400 $READ_TMP/big.md"; do
  check "the read-cap refusal says the cap does not rise: ${ESC%% *}" 1 \
    "$(cd "$MAIN_TMP" && json "$ESC" | "$HOOK" 2>&1 >/dev/null | grep -q 'THE CAP DOES NOT RISE' && echo 1 || echo 0)"
done

part 3
# --- required instructions are readable in one call -------------------------
# The cap exempts the documents an agent is ordered to read whole:
# AGENT_STARTUP.md, a unit brief, and a SKILL.md under a skills root. Each
# OPERAND is judged, never the command line, so an exempt file beside a large
# ordinary one, or a quoted mention of SKILL.md, grants nothing.
mkdir -p "$READ_TMP/.claude/briefs" "$READ_TMP/.agents/skills/ponytail" "$READ_TMP/docs"
for f in AGENT_STARTUP.md .claude/briefs/unit-x.md .agents/skills/ponytail/SKILL.md docs/SKILL.md src.ts run.log; do
  cp "$READ_TMP/big.md" "$READ_TMP/$f"
done
check "cat of AGENT_STARTUP.md by absolute path passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/AGENT_STARTUP.md")")"
check "cat of AGENT_STARTUP.md by relative path passes" 0 \
  "$( (cd "$READ_TMP" && json 'cat AGENT_STARTUP.md' | "$HOOK" >/dev/null 2>&1; echo $?) )"
check "nl of a unit brief by relative path passes" 0 \
  "$( (cd "$READ_TMP" && json 'nl -ba .claude/briefs/unit-x.md' | "$HOOK" >/dev/null 2>&1; echo $?) )"
check "sed range of a skill's SKILL.md passes" 0 \
  "$(run_hook "$(json "sed -n '1,400p' $READ_TMP/.agents/skills/ponytail/SKILL.md")")"
check "head over the cap of a brief passes" 0 \
  "$(run_hook "$(json "head -400 $READ_TMP/.claude/briefs/unit-x.md")")"
check "tail over the cap of a skill passes" 0 \
  "$(run_hook "$(json "tail -300 $READ_TMP/.agents/skills/ponytail/SKILL.md")")"
check "the startup range read observed by the plan author passes" 0 \
  "$(run_hook "$(json "sed -n '1,220p' AGENT_STARTUP.md")")"
check_try "a SKILL.md outside a skills root is ordinary markdown" \
  "cat $READ_TMP/docs/SKILL.md"
# A skills root is an agent config directory (.claude, .codex, .codex-review,
# .agents), for the repo or installed plugins; a directory merely named skills
# is not one.
mkdir -p "$READ_TMP/project/skills/vendor" "$READ_TMP/.claude/plugins/cache/m/p/1.0/skills/s" "$READ_TMP/.codex/skills/s" "$READ_TMP/.codex-review/skills/.system/s"
for f in project/skills/vendor/SKILL.md .claude/plugins/cache/m/p/1.0/skills/s/SKILL.md .codex/skills/s/SKILL.md .codex-review/skills/.system/s/SKILL.md; do
  cp "$READ_TMP/big.md" "$READ_TMP/$f"
done
check_try "a SKILL.md under a bare skills directory is ordinary markdown" \
  "cat $READ_TMP/project/skills/vendor/SKILL.md"
check "an installed plugin's SKILL.md passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/.claude/plugins/cache/m/p/1.0/skills/s/SKILL.md")")"
check "a Codex skill's SKILL.md passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/.codex/skills/s/SKILL.md")")"
check "a review-lane Codex system skill's SKILL.md passes" 0 \
  "$(run_hook "$(json "sed -n '1,400p' $READ_TMP/.codex-review/skills/.system/s/SKILL.md")")"
check_try "a large source file still blocks" \
  "sed -n '1,400p' $READ_TMP/src.ts"
check_try "a large log still blocks" \
  "head -400 $READ_TMP/run.log"
check_try "an exempt file beside a large ordinary file blocks (cat)" \
  "cat $READ_TMP/AGENT_STARTUP.md $READ_TMP/big.md"
check_try "an exempt brief beside a large source file blocks (sed)" \
  "sed -n '1,400p' $READ_TMP/.claude/briefs/unit-x.md $READ_TMP/src.ts"
check_try "a quoted SKILL.md mention grants nothing to a later read" \
  "rg -n 'SKILL.md' docs; cat $READ_TMP/big.md"
check_try "a brief path climbing out with .. is not a brief" \
  "cat $READ_TMP/.claude/briefs/../../big.md"
check_try "a piped sed over the cap names no exempt operand and blocks" \
  "git show HEAD:AGENT_STARTUP.md | sed -n '1,400p'"
# A separated count is still not a file operand: the required-document
# exemption reads the files, and the number beside -n is not one of them.
check "head -n over the cap of a brief passes" 0 \
  "$(run_hook "$(json "head -n 400 $READ_TMP/.claude/briefs/unit-x.md")")"
check "tail --lines= over the cap of a skill passes" 0 \
  "$(run_hook "$(json "tail --lines=300 $READ_TMP/.agents/skills/ponytail/SKILL.md")")"
check_try "a separated count does not excuse a source file beside a brief" \
  "head -n 400 $READ_TMP/.claude/briefs/unit-x.md $READ_TMP/src.ts"
rm -rf "$READ_TMP"
# The heap cap is agent-independent and stays that way.
check "a Codex payload still gets the heap cap" 2 \
  "$(AGENT_KIND=codex bash -c 'echo "$1" | "$0" >/dev/null 2>&1; echo $?' "$HOOK" "$(json 'node --test x.test.ts')")"

# --- repo-wide text search -------
check_try "rg with a bare pattern and no path blocks" \
  'rg foo'
check_try "rg with a quoted pattern and no path blocks" \
  "rg -n 'foo bar'"
check_try "rg over . blocks" \
  "rg -n 'foo' ."
check_try "rg over the checkout root blocks" \
  "rg foo $MAIN_TMP"
check_try "grep -r over . blocks" \
  'grep -rn foo .'
check_try "rg piped into head still blocks" \
  "rg 'foo' | head"
check "rg with a directory passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' src/services")")"
check "rg with a bare pattern and an existing directory passes" 0 \
  "$(run_hook "$(json 'rg foo .claude/scripts')")"
check "rg with a root file and no directory passes" 0 \
  "$(run_hook "$(json "rg 'foo' package.json")")"
check "rg with a quoted pattern and a nested path passes" 0 \
  "$(run_hook "$(json "rg -l 'foo' web/src/pages")")"
check "grep without -r passes" 0 \
  "$(run_hook "$(json 'grep foo package.json')")"
check "grep -r with a directory passes" 0 \
  "$(run_hook "$(json 'grep -rn foo src/routes')")"

# BOUNDED IS ANYTHING BELOW THE ROOT. About 20 of 55 refusals were real
# bounded searches: a top-level folder off the old allowlist, a glob, a path
# after the command's own cd. The root, its parents and a pathless search stay out.
mkdir -p "$MAIN_TMP/policy" && touch "$MAIN_TMP/tsconfig.json" "$MAIN_TMP/tsconfig.web.json"
LOG_TMP=$(mktemp -d) && touch "$LOG_TMP/file.log"
check "rg over a top-level folder off the old allowlist passes" 0 \
  "$(run_hook "$(json 'rg x policy')")"
check "rg over a glob of root files passes" 0 \
  "$(run_hook "$(json 'rg x tsconfig*.json')")"
check "rg over a bare wildcard inside a folder passes" 0 \
  "$(run_hook "$(json 'rg x policy/*')")"
check "rg over a file named relative to the command's own cd passes" 0 \
  "$(run_hook "$(json "cd $LOG_TMP && rg x file.log")")"
check_try "rg x with no path still blocks" 'rg x'
check_try "rg x . from the root still blocks" 'rg x .'
check_try "rg x .. from the root still blocks" 'rg x ..'
check_try "a bare * glob is the whole checkout and still blocks" 'rg x *'
check_try "rg . after a cd to the checkout's parent still blocks" "cd $MAIN_TMP/.. && rg x ."
# A FAILED cd DOES NOT MOVE THE SHELL, so it must not move the search base: with
# `;` the rg still runs in the checkout root. `&&` is judged the same way.
check_try "rg . after a failed cd into a missing child still blocks" "cd $MAIN_TMP/missing; rg needle ."
check_try "rg . after a failed cd with && blocks the same way" "cd $MAIN_TMP/missing && rg needle ."
check "a failed cd keeps the old base for a bounded file" 0 \
  "$(run_hook "$(json "cd $MAIN_TMP/missing; rg x package.json")")"
rm -rf "$LOG_TMP"
# A VARIABLE AFTER A FIXED PREFIX IS JUDGED AS A GLOB FROM THE `$` ON. 19 of 20
# unbounded refusals on 2026-09-27 named a log such as /tmp/demo-logs/x-$n.log.
check "rg over an absolute log path holding a variable passes" 0 \
  "$(run_hook "$(json 'rg x /tmp/demo-logs/x-$n.log')")"
check "rg over a relative folder holding a variable passes" 0 \
  "$(run_hook "$(json 'rg x policy/$f')")"
check_try "rg over a bare variable still blocks" 'rg x $X'
check_try "rg over a variable right under / still blocks" 'rg x /$X'
check_try "rg over a variable at the checkout root still blocks" "rg x $MAIN_TMP/\$X"
check_try "rg over a variable in the checkout's parent still blocks" "rg x $MAIN_TMP/../\$X"
# A LOOP VARIABLE BOUND TO BOUNDED PATHS IS BOUNDED. Only a one-word
# for-list resolved, so `for f in a b; do rg x "$f"; done` was refused though
# every value it can take is a bounded path.
check "a for loop over two bounded paths lets rg \"\$f\" pass" 0 \
  "$(run_hook "$(json 'for f in policy package.json; do rg x "$f"; done')")"
check "a for loop over a bounded glob and a file lets rg \$f pass" 0 \
  "$(run_hook "$(json 'for f in policy/* package.json; do rg x $f; done')")"
check "a later reassignment of the loop variable does not undo the loop's binding" 0 \
  "$(run_hook "$(json 'for f in policy package.json; do rg x "$f"; done; f=package.json')")"
check_try "a for loop with the checkout root among its paths still blocks" 'for f in policy .; do rg x "$f"; done'
check_try "a for loop whose list holds a variable still blocks" 'for f in policy $X; do rg x "$f"; done'
check_try "a bare pathless rg inside a for loop still blocks" 'for f in policy package.json; do rg x; done'
# A VARIABLE BOUND BY `read` IS A LIST OF PATHS FED IN, ONE AT A TIME:
# each `rg "$f"` searches one listed path, never a bare repo-wide search, so it
# passes. What feeds the list is not judged (a read fed the checkout root is the
# accepted residual). `D=$(...)` stays refused: its value is unknown.
check "a while-read loop lets rg \"\$f\" pass" 0 \
  "$(run_hook "$(json 'git diff --name-only | while IFS= read -r f; do rg -n x "$f"; done')")"
check "a plain read binding lets rg \${f} pass" 0 \
  "$(run_hook "$(json 'while read f; do rg x ${f}; done < /tmp/demo-logs/list')")"
check "a read with an input redirect binds its variable too" 0 \
  "$(run_hook "$(json 'read -r f < /tmp/demo-logs/list; rg x "$f"')")"
check_try "a read binding does not bound another variable" 'while read -r f; do rg x "$g"; done < /tmp/demo-logs/list'
check_try "a later literal reassignment replaces the read binding" 'read -r f < /tmp/demo-logs/list; f=.; rg x "$f"'
check_try "a command-substitution assignment still blocks" 'D=$(git rev-parse --show-toplevel); rg x "$D"'
check_try "a bare pathless rg inside a read loop still blocks" 'while read -r f; do rg x; done < /tmp/demo-logs/list'

# THE REFUSAL NAMES THE WHOLE-REPO FORM. This is the most-fired rule in
# the repo, and 19 of 51 blocks were followed by another block of the same rule,
# because it said what was forbidden and never what to ask instead.
SEARCH_REFUSAL=$(cd "$MAIN_TMP" && json 'rg -n foo .' | "$HOOK" 2>&1 >/dev/null)
check "the unbounded refusal names codebase-memory search_code" 1 \
  "$(grep -q 'search_code' <<<"$SEARCH_REFUSAL" && echo 1 || echo 0)"

# A SESSION'S OWN TRANSCRIPTS ARE SEARCHABLE. They live under
# ~/.claude/projects/<project>/, outside every checkout, and both home forms
# were refused as unbounded before the path was ever resolved.
check "rg under ~/.claude/projects passes" 0 \
  "$(run_hook "$(json 'rg -n foo ~/.claude/projects/-home-x')")"
check "rg under \$HOME/.claude/projects passes" 0 \
  "$(run_hook "$(json 'rg -n foo $HOME/.claude/projects/-home-x')")"
# The home directory itself still holds every checkout, so it stays refused.
check_try "rg over the home directory still blocks" \
  'rg -n foo ~'
check "git grep passes" 0 \
  "$(run_hook "$(json 'git grep -n foo')")"
check "grep as a filter passes" 0 \
  "$(run_hook "$(json 'npm run typecheck 2>&1 | grep -c error')")"

part 4
# --- raw pane reads keep main's context lean (orchestrator invariant 5) ------
# A pane buffer is ~190 KB of one-line TUI repaint fragments, so piping it to
# `tail -n` bounds the line count and not the bytes; read-verdict.sh filters it
# outside main's context.
check "accumulated pane read blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --cursor 0 --limit 100000 --json')")"
check "pane read with no limit blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --json')")"
check "pane read piped to tail still blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --limit 400 | tail -130')")"
# Every variant blocks: the viewport is TUI fragments too, and `terminal list`
# answers liveness without a pane read (owner ruling 2026-09-13).
check "pane read with --screen blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --screen --json')")"
check "pane read under the old 200-line cap blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --limit 20 --json')")"
# The guard matches the command, not the phrase: writing ABOUT a pane read is
# not a pane read, and a substring match blocked the commit that removed the
# --screen carve-out.
check "a commit message naming the command passes" 0 \
  "$(run_hook "$(json 'git commit -m "block every orca-ide terminal read variant"')")"
check "a pane read after a pipe still blocks" 2 \
  "$(run_hook "$(json 'true && orca-ide terminal read --terminal term_abc --json')")"
check "read-verdict.sh passes" 0 \
  "$(run_hook "$(json 'bash scripts/read-verdict.sh term_abc 400')")"
check "an unrelated orca-ide call passes" 0 \
  "$(run_hook "$(json 'orca-ide orchestration run-current --json')")"
# A global option before the subcommand is the same call. Every check
# read fixed word positions, so a leading `--json` walked past all of them.
check "a leading --json does not hide a pane read" 2 \
  "$(run_hook "$(json 'orca-ide --json terminal read --terminal term_abc')")"
check "an option between the subcommand words does not hide a pane read" 2 \
  "$(run_hook "$(json 'orca-ide terminal --json read --terminal term_abc')")"
check "the orca name reads a pane the same way" 2 \
  "$(run_hook "$(json 'orca --json terminal read --terminal term_abc')")"
check "an assignment prefix and a leading --json do not hide a pane read" 2 \
  "$(run_hook "$(json 'ORCA_DEBUG=1 orca-ide --json terminal read --terminal term_abc')")"
# An option that takes a value takes the next word with it, so the value is not
# read as the subcommand.
check "a leading --environment and its value do not hide a pane read" 2 \
  "$(run_hook "$(json 'orca-ide --environment dev terminal read --terminal term_abc')")"
check "a leading --terminal and its handle do not hide a pane read" 2 \
  "$(run_hook "$(json 'orca-ide --terminal term_abc --limit 20 terminal read')")"
check "a commit message naming the --json form passes" 0 \
  "$(run_hook "$(json 'git commit -m "block orca-ide --json terminal read too"')")"
check "an unrelated orca-ide call behind a leading --json passes" 0 \
  "$(run_hook "$(json 'orca-ide --json orchestration run-current')")"
# --- main may work in a worker's worktree (the owner 2026-09-25) --------------------
# The block on main reading or opening a worktree was removed; these keep it gone.
WT_FIXTURE=$HOME/orca/workspaces/demo-project/unit-x
check "main may cd into a worktree" 0 "$(run_hook "$(json "cd $WT_FIXTURE")")"
check "main may read a worktree file" 0 "$(run_hook "$(json "cat $WT_FIXTURE/src/a.ts")")"
check "main may git show in a worktree" 0 "$(run_hook "$(json "git -C $WT_FIXTURE show HEAD:src/a.ts")")"

# A worker lives in the worktree and must be unaffected. Its seat is a linked
# worktree, where git-dir and git-common-dir differ; build a real one rather
# than stubbing the test, because the stub is the thing most likely to drift.
WORKER_TMP=$(mktemp -d)
git -C "$WORKER_TMP" init -q 2>/dev/null
git -C "$WORKER_TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x 2>/dev/null
git -C "$WORKER_TMP" worktree add -q "$WORKER_TMP/wt" -b wtb >/dev/null 2>&1
run_hook_in() { ( cd "$1" 2>/dev/null && echo "$2" | "$HOOK" >/dev/null 2>&1; echo $? ); }

check "a worker seat may cd inside its own worktree" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json "cd $WT_FIXTURE")")"
check "a worker seat may read files under the workspaces root" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json "cat $WT_FIXTURE/package.json")")"
check "a worker seat still gets the heap cap" 2 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'node --test x.test.ts')")"
check "a reviewer seat is exempt from the worktree block" 0 \
  "$(COMMANDECK_REVIEWER=1 bash -c 'echo "$1" | "$0" >/dev/null 2>&1; echo $?' "$HOOK" "$(json "cat $WT_FIXTURE/package.json")")"
check "a reviewer seat still gets the heap cap" 2 \
  "$(COMMANDECK_REVIEWER=1 bash -c 'echo "$1" | "$0" >/dev/null 2>&1; echo $?' "$HOOK" "$(json 'node --test x.test.ts')")"
check "a worker seat may use a task-list" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'orca-ide orchestration task-list --json')")"
# R1 is a worker's logged call: a skill and a fix-round brief, both over the
# line cap, read whole because the instructions require it.
R1=$(cat <<'EOF'
sed -n '1,240p' /home/dev/orca/workspaces/demo-project/u1203-budget-not-user-speed/.agents/skills/ponytail/SKILL.md && sed -n '1,260p' .claude/briefs/u1203-budget-not-user-speed-fix-r3-advice.md
EOF
)
check "R1: a worker reads a SKILL.md and a brief whole" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json "$R1")")"
check_try "a worker still gets the read cap on a source range" \
  "sed -n '1,400p' src/services/verification-service.ts" "$WORKER_TMP/wt"

check "a worker seat may tail -f into grep" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'tail -n 0 -f /tmp/demo-logs/x.log | grep -q -m1 DONE')")"
check "a worker seat may gh run watch" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'gh run watch 1234567890')")"
# Reading past a leading option moves no rule across the boundary: the
# wake rules stay main's, and a raw pane read stays refused for every seat.
check "a worker seat may gh -R run watch" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'gh -R owner/repo run watch 1234567890')")"
check "a worker seat may use a task-list behind a leading --json" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'orca-ide --json orchestration task-list')")"
check "a worker seat still may not read a raw pane behind a leading --json" 2 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'orca-ide --json terminal read --terminal term_abc')")"
check "a reviewer seat still may not read a raw pane behind a leading --json" 2 \
  "$(COMMANDECK_REVIEWER=1 bash -c 'echo "$1" | "$0" >/dev/null 2>&1; echo $?' "$HOOK" "$(json 'orca-ide --json terminal read --terminal term_abc')")"
check "a worker seat may run local-checks directly" 0 \
  "$(run_hook_in "$WORKER_TMP/wt" "$(json 'bash scripts/ci/local-checks.sh --full')")"
rm -rf "$WORKER_TMP"

part 5
# --- kill that can reach main's own session (owner ruling 2026-09-17) ----------
# The incident: `kill -TERM -3786748 -3978349` signalled a process GROUP that
# main's own CLI sat in, and killed the session. A bare-pid kill of a stray
# waiter is the supported form and must still pass.
check "negative-pid target blocks (process group)" 2 \
  "$(run_hook "$(json 'kill -TERM -3786748 -3978349')")"
check "negative pid with no signal blocks" 2 \
  "$(run_hook "$(json 'kill -3786748')")"
check "kill -9 -1 blocks" 2 \
  "$(run_hook "$(json 'kill -9 -1')")"
check "killing this hook's own parent blocks" 2 \
  "$(run_hook "$(json "kill -TERM $PPID")")"
check "pkill on claude blocks" 2 \
  "$(run_hook "$(json 'pkill -f claude')")"
check "killall node blocks" 2 \
  "$(run_hook "$(json 'killall node')")"
check "negative pid after a && still blocks" 2 \
  "$(run_hook "$(json 'echo hi && kill -TERM -3786748')")"

check "bare-pid kill passes" 0 \
  "$(run_hook "$(json 'kill -TERM 3786748 3978349')")"
check "kill -9 with a bare pid passes" 0 \
  "$(run_hook "$(json 'kill -9 3786748')")"
check "kill -s TERM with a bare pid passes" 0 \
  "$(run_hook "$(json 'kill -s TERM 3786748')")"
check "pkill on an unrelated name passes" 0 \
  "$(run_hook "$(json 'pkill -f my-stray-script')")"

# The same reach by other spellings. Pid 0 is the caller's own process
# group; an unexpanded target is a pid nobody read; -u takes every process the
# user owns; and a protected name is the same name in any case or behind a
# regex. Each refused shape has an allowed neighbour, so the rule cannot pass
# by refusing every kill. Single quotes keep `$` and backticks as typed.
for KILL_CMD in 'kill 0' 'kill -TERM 0' 'kill -s TERM 0' 'kill -TERM 3786748 0' \
  'kill $PPID' 'kill $$' 'kill "$PPID"' 'kill -TERM $WAITER' \
  'kill $(pgrep claude)' 'kill `pgrep claude`' 'kill "$(pgrep claude)"' 'kill -9 "`pgrep claude`"' \
  'pkill -u max' 'killall -u max' 'pkill --uid max' 'pkill --uid=max' 'pkill -umax' 'pkill -U max' \
  'killall Claude' 'pkill -f NODE' 'pkill -f Orca-IDE' \
  "pkill -9 -f 'cl[a]ude'" 'pkill -f n.de' "pkill -f 'cl[a]ude --remote-control'"; do
  check "refuses: $KILL_CMD" 2 "$(run_hook "$(json "$KILL_CMD")")"
done
for KILL_CMD in 'kill 0' 'kill $PPID' 'kill $(pgrep claude)' 'pkill -u max' 'killall Claude' "pkill -9 -f 'cl[a]ude'"; do
  check "refuses after &&: $KILL_CMD" 2 "$(run_hook "$(json "echo hi && $KILL_CMD")")"
done
for KILL_CMD in 'kill -0 3786748' 'kill -TERM 3786748' 'kill -n 15 3786748' 'kill -s 0 3786748' \
  'echo hi && kill -0 3786748' "echo 'kill \$PPID'" "echo 'kill \$(pgrep claude)'" "echo 'kill 0'" \
  'killall my-stray-script' "echo 'killall Claude'" "echo 'pkill -u max'" \
  "pkill -f 'my-stray-[s]cript'" 'pkill -USR1 my-stray-script' 'pkill -9 -f my-stray-script'; do
  check "passes: $KILL_CMD" 0 "$(run_hook "$(json "$KILL_CMD")")"
done

# A job the SAME command started. `$!` is the pid of a child of the
# command's own shell, so it can never be main or an ancestor. The name must be
# set by a plain `NAME=$!` before the kill and appear nowhere else in the
# command except as `$NAME` / `${NAME}`; nothing is evaluated, so any other
# mention is refused. Both seats: the disposable main and this worktree.
KILL_WT=$(cd "$(dirname "$0")/../.." && pwd)
for KILL_CMD in 'npm run dev & SERVER=$!; sleep 5; kill -TERM "$SERVER"' 'sleep 30 & W=$!; kill $W' \
  'sleep 30 & W=$!; kill -9 $W' 'sleep 30 & W=$!; kill -s TERM "${W}"' 'sleep 30 & W=$!; kill -n 15 ${W}' \
  'sleep 1 & A=$!; sleep 2 & B=$!; kill $A "$B"' 'sleep 30 & W=$!; kill -TERM $W 3786748' \
  'sleep 30 & W=$!; echo "stopping $W"; kill $W' 'sleep 1 & W=$!; wait $W; sleep 2 & W=$!; kill $W' \
  $'sleep 30 &\nW=$!\nsleep 1 && kill "$W"' 'if true; then sleep 30 & W=$!; fi; sudo kill $W'; do
  check "passes, child job: $KILL_CMD" 0 "$(run_hook "$(json "$KILL_CMD")")"
  check "passes in a worktree, child job: $KILL_CMD" 0 "$(run_hook_in "$KILL_WT" "$(json "$KILL_CMD")")"
done
for KILL_CMD in 'sleep 30 & kill $W; W=$!' 'W=123; kill $W' 'W=$PPID; kill $W' 'W=$(pgrep claude); kill $W' \
  'sleep 1 & X=$!; W=$X; kill $W' 'sleep 1 & W=$!; W=$PPID; kill $W' 'W=$PPID; sleep 1 & W=$!; kill $W' \
  'sleep 1 & W=$!; kill $W; W=1' 'sleep 1 & W=$!; read W; kill $W' 'sleep 1 & W=$!; read \W; kill $W' \
  'sleep 1 & W=$!; read "W"; kill $W' 'sleep 1 & W=$!; for W in 1; do kill $W; done' \
  'sleep 1 & W=$!; : ${W:=1}; kill $W' 'sleep 1 & W=$!; W+=0; kill $W' 'sleep 1 & W=$!; declare "W=1 "; kill $W' \
  'echo "W=$!"; kill $W' "echo 'W=\$!'; kill \$W" 'echo W=$!; kill $W' $'# W=$!\nkill $W' \
  $'cat <<EOF\nW=$!\nEOF\nkill $W' 'sleep 1 & W=$!; echo "W=$!"; kill $W' \
  'sleep 1 & W="$!"; kill $W' 'sleep 1 & W=$!0; kill $W' 'sleep 1 & W=$!\0; kill $W' 'sleep 1 & W=$!"0"; kill $W' \
  'sleep 1 & export W=$!; kill $W' 'sleep 1 & W=$! true; kill $W' \
  'sleep 1 & W=$!; kill $W $PPID' 'sleep 1 & W=$!; kill $W 0' 'sleep 1 & W=$!; kill $W -5' 'sleep 1 & W=$!; kill $W $$' \
  'sleep 1 & W=$!; kill ${W:-1}' 'sleep 1 & W=$!; kill $W$W' 'sleep 1 & W=$!; kill "$W"0' 'sleep 1 & W=$!; kill $(echo $W)' \
  'PPID=$!; kill $PPID' 'sleep 1 & BASHPID=$!; kill $BASHPID' 'sleep 1 & RANDOM=$!; kill $RANDOM' 'kill $!'; do
  check "refuses, not a child job: $KILL_CMD" 2 "$(run_hook "$(json "$KILL_CMD")")"
  check "refuses in a worktree, not a child job: $KILL_CMD" 2 "$(run_hook_in "$KILL_WT" "$(json "$KILL_CMD")")"
done
# A name the session already exports is not the child's: an assignment the
# shell never reaches (a dead branch, a subshell) leaves the inherited value.
check "refuses a child-job name the environment already sets" 2 \
  "$(cd "$MAIN_TMP" && json 'sleep 1 & KILL_INHERITED=$!; kill $KILL_INHERITED' | KILL_INHERITED=1 "$HOOK" >/dev/null 2>&1; echo $?)"
# Nor is a name the SHELL sets by itself, in bash or in zsh: in a branch that
# never runs the assignment is skipped and the shell's own value is what gets
# killed -- PIPESTATUS, SECONDS and status can all be 0, the caller's own
# group. One refusal per listed name and one per name family (BASH*, ZSH*,
# zsh_*, COMP_*, EPOCH*, PROMPT*, PS[0-4], TRY_BLOCK_*, dis_*, HIST*, MAIL*).
# Sixteen at a time: one hook run each would add half a minute to this file.
check "refuses the shell's own name set in a branch that never runs" 2 \
  "$(run_hook "$(json 'if false; then sleep 1 & PIPESTATUS=$!; fi; true; kill "$PIPESTATUS"')")"
KILL_SHELL_NAMES='BASHPID BASH_SUBSHELL ZSH_SUBSHELL zsh_eval_context COMP_WORDBREAKS EPOCHSECONDS PROMPT PS4
  TRY_BLOCK_ERROR dis_aliases HISTCMD HISTSIZE MAILCHECK
  PPID UID EUID GID EGID GROUPS RANDOM SRANDOM SECONDS LINENO OPTIND OPTERR OPTARG SHLVL PIPESTATUS pipestatus status
  COLUMNS LINES REPLY reply MAPFILE COPROC FUNCNAME FUNCNEST DIRSTACK dirstack ARGC argv ERRNO TTY TTYIDLE
  MATCH MBEGIN MEND match mbegin mend IFS PATH path PWD OLDPWD HOME SHELL SHELLOPTS TERM HOSTNAME HOSTTYPE HOST
  MACHTYPE OSTYPE CPUTYPE VENDOR USERNAME LOGNAME KEYBOARD_HACK KEYTIMEOUT LISTMAX SAVEHIST NULLCMD READNULLCMD
  SPROMPT TIMEFMT TMPPREFIX WORDCHARS WATCH watch PSVAR psvar prompt CDPATH cdpath FIGNORE fignore FPATH fpath
  MANPATH manpath MODULE_PATH module_path aliases galiases saliases builtins commands functions functions_source
  funcfiletrace funcsourcetrace funcstack functrace histchars history historywords jobdirs jobstates jobtexts
  keymaps mailpath modules nameddirs options parameters patchars reswords signals termcap terminfo userdirs
  usergroups widgets _'
KILL_TMP=$(mktemp -d); KILL_PIDS=()
for KILL_N in $KILL_SHELL_NAMES; do
  run_hook "$(json "sleep 1 & $KILL_N=\$!; kill \$$KILL_N")" > "$KILL_TMP/$KILL_N" &
  KILL_PIDS+=($!)
  [ ${#KILL_PIDS[@]} -lt 16 ] || { wait "${KILL_PIDS[@]}"; KILL_PIDS=(); }
done
[ ${#KILL_PIDS[@]} -eq 0 ] || wait "${KILL_PIDS[@]}"
for KILL_N in $KILL_SHELL_NAMES; do
  check "refuses a child-job name the shell sets itself: $KILL_N" 2 "$(cat "$KILL_TMP/$KILL_N")"
done
rm -rf "$KILL_TMP"
# The `$?`-style specials are not names at all, so no assignment can vouch.
for KILL_CMD in 'kill $?' 'kill $#' 'kill $-' 'kill $0' 'kill $1' 'kill $@' 'kill $*' 'kill ${?}' 'kill "${1}"'; do
  check "refuses a special parameter: $KILL_CMD" 2 "$(run_hook "$(json "sleep 1 & W=\$!; $KILL_CMD")")"
done

# A process group behind a variable. `kill -TERM -12345` was refused
# and `kill -TERM -$PPID` was not: a `-` before an unexpanded value read as a
# flag. Nobody has read that value, so it is refused wherever it sits -- first
# place too, where a number over 64 is a group and not a signal. A signal from
# a variable has a safe spelling (`-s "$SIG"`), and a child job is killed by
# pid, never by group.
for KILL_CMD in 'kill -TERM -$PPID' 'kill -- -$PPID' 'kill -TERM -"$PGID"' 'kill -9 -${PGID}' \
  'kill -TERM -$(pgrep -o claude)' 'kill -TERM -`pgrep -o claude`' 'kill -9 -"$(pgrep -o claude)"' \
  'kill -s TERM -$PGID' 'kill -n 15 -- -$PGID' 'kill -TERM "-$PGID"' 'kill -TERM 3786748 -$PGID' 'kill -$PPID' \
  'echo hi && kill -TERM -$PPID' 'sleep 30 & W=$!; kill -TERM -$W' 'sleep 30 & W=$!; kill -- -"${W}"'; do
  check "refuses a group behind a variable: $KILL_CMD" 2 "$(run_hook "$(json "$KILL_CMD")")"
  check "refuses a group behind a variable in a worktree: $KILL_CMD" 2 "$(run_hook_in "$KILL_WT" "$(json "$KILL_CMD")")"
done
for KILL_CMD in 'kill 3786748' 'kill -- 3786748' 'kill -s "$SIG" 3786748' 'sleep 30 & W=$!; kill -- $W' \
  'sleep 30 & W=$!; kill -s "$SIG" "$W"' "echo 'kill -TERM -\$PPID'"; do
  check "passes beside the group refusal: $KILL_CMD" 0 "$(run_hook "$(json "$KILL_CMD")")"
done

# The serena-down marker stands the symbols gates down. Only read-tracker.sh
# writes it, on an errored serena call; a worker that touches it by hand runs
# a whole cut with the gates off (2026-09-18).
check "touching the serena-down marker is refused" 2 \
  "$(run_hook "$(json 'touch /tmp/claude-serena-down-abc123')")"
check "writing the marker through a redirect is refused" 2 \
  "$(run_hook "$(json 'echo > "/tmp/claude-serena-down-$SID"')")"
check "an unrelated touch in /tmp passes" 0 \
  "$(run_hook "$(json 'touch /tmp/claude-other-marker')")"


# A read after an inline `cd` is of the file in that folder, not of one by the
# same name where the command started.
READ_TMP=$(mktemp -d)
printf 'one line\n' >"$READ_TMP/small.md"
head -c 40000 /dev/zero | tr '\0' 'x' >"$READ_TMP/big.md"
check "a whole-file cat after an inline cd is still capped" 2 \
  "$(cd "$MAIN_TMP" && json "cd $READ_TMP && cat big.md" | "$HOOK" >/dev/null 2>&1; echo $?)"
check "a small file after an inline cd passes" 0 \
  "$(cd "$MAIN_TMP" && json "cd $READ_TMP && cat small.md" | "$HOOK" >/dev/null 2>&1; echo $?)"
rm -rf "$READ_TMP"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

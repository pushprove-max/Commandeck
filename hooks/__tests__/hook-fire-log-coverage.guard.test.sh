#!/usr/bin/env bash
# Drift guard: every hook arms the fire log before its first decision,
# so a hook added without the wiring, or one that loses it, fails here instead
# of going quietly missing from scripts/hook-fire-log-summary.sh. A hook that
# prints a permissionDecision "ask" must set HOOK_FIRE_ASK=1, or its asks are
# logged as allows.
#
# The inventory is every top-level hooks/*.sh plus every command
# hooks/hooks.json registers. lib/ and __tests__/ are not invocations, so
# neither is in it. A registered hook that is not a shell script fails: the shell
# wiring is the only kind defined, and an unknown extension is not skipped.
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $*"; }

# prints "checked N" and one line per problem; exits 1 on any problem
check_tree() {
  python3 - "$1" <<'PY'
import json, os, re, sys
root = os.path.realpath(sys.argv[1])
hooks = os.path.join(root, "hooks")
# A real source-and-arm command at the top level: not a comment, not inside a
# function or a branch, not text another command prints.
ARM = re.compile(r'^(\.|source) .*/lib/hook-fire-log\.sh"? 2>/dev/null && hook_fire_log_arm( |$)')
FUNC = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{')
DECISION = re.compile(r'\bexit\b|\breturn\b|decision|additionalContext|systemMessage|>&2')
ASK = re.compile(r'permissionDecision\\?"?\s*:\s*\\?"ask')
ASK_MARK = re.compile(r'^[^#]*\bHOOK_FIRE_ASK=1\b', re.M)
inventory, problems = set(), []
for name in os.listdir(hooks):
    path = os.path.join(hooks, name)
    if name.endswith(".sh") and os.path.isfile(path):
        inventory.add(os.path.realpath(path))
for groups in json.load(open(os.path.join(hooks, "hooks.json"))).get("hooks", {}).values():
    for group in groups:
        for hook in group.get("hooks", []):
            words = hook.get("command", "").split()
            # Every hook is started through the launcher: the hook is the word after it.
            words = [w for w in words if not w.endswith('/hooks/lib/run-hook.sh"')]
            word = words[0] if words else ""
            path = word.strip(chr(34)).replace("${CLAUDE_PLUGIN_ROOT}", root)
            if not path.endswith(".sh"):
                problems.append(f"{word}: a registered hook that is not a shell script has no fire-log wiring")
            elif not os.path.isfile(path):
                problems.append(f"{word}: registered but missing")
            else:
                inventory.add(os.path.realpath(path))
for path in sorted(inventory):
    armed = first = None
    in_func = False
    for number, line in enumerate(open(path, errors="replace"), 1):
        if in_func:
            in_func = not line.startswith("}")
            continue
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        if FUNC.match(line):
            in_func = not text.endswith("}")
            continue
        if armed is None and ARM.match(line):
            armed = number
        elif first is None and DECISION.search(line):
            first = number
    rel = os.path.relpath(path, root)
    # macOS /bin/bash is 3.2, under which the fire log writes nothing.
    if open(path, errors="replace").readline().strip() != "#!/usr/bin/env bash":
        problems.append(f"{rel}: shebang is not #!/usr/bin/env bash")
    if armed is None:
        problems.append(f"{rel}: never sources lib/hook-fire-log.sh and calls hook_fire_log_arm")
    elif first is not None and first < armed:
        problems.append(f"{rel}: line {first} can decide before the fire log is armed on line {armed}")
    source = open(path, errors="replace").read()
    if ASK.search(source) and not ASK_MARK.search(source):
        problems.append(f"{rel}: prints a permissionDecision \"ask\" without setting HOOK_FIRE_ASK=1")
print(f"checked {len(inventory)}")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
}

# The real tree passes, and the inventory is not vacuous.
OUT=$(check_tree "$ROOT"); rc=$?
[ "$rc" = 0 ] && ok || bad "this tree: $OUT"
want=$(ls "$ROOT"/hooks/*.sh | wc -l | tr -d ' ')
[ "$(head -1 <<<"$OUT")" = "checked $want" ] && ok || bad "inventory: $(head -1 <<<"$OUT"), want checked $want"

fixture() { # -> prints a fresh copy of this tree's hooks and settings
  local d
  d=$(mktemp -d "$T/fx.XXXXXX")
  mkdir -p "$d/hooks"
  cp "$ROOT"/hooks/*.sh "$d/hooks/" && cp -R "$ROOT/hooks/lib" "$d/hooks/lib"
  cp "$ROOT/hooks/hooks.json" "$d/hooks/hooks.json"
  printf '%s' "$d"
}
rejects() { # label pattern tree
  local out
  if out=$(check_tree "$3"); then bad "$1: accepted"
  elif grep -qE "$2" <<<"$out"; then ok
  else bad "$1: rejected for the wrong reason: $out"; fi
}
ARMLINE='. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"'

F=$(fixture)
printf '#!/usr/bin/env bash\nINPUT=$(cat)\necho no >&2\nexit 2\n' > "$F/hooks/new-guard.sh"
rejects "an added hook with no wiring" 'new-guard\.sh: never sources' "$F"

F=$(fixture)
jq '.hooks.PreToolUse += [{matcher:"Bash", hooks:[{type:"command", command:"${CLAUDE_PLUGIN_ROOT}/hooks/new-guard.py"}]}]' \
  "$ROOT/hooks/hooks.json" > "$F/hooks/hooks.json"
rejects "a registered non-shell hook" 'new-guard\.py: a registered hook that is not a shell script' "$F"

F=$(fixture)
grep -vF "$ARMLINE" "$ROOT/hooks/git-safety.sh" > "$F/hooks/git-safety.sh"
rejects "a removed source call" 'git-safety\.sh: never sources' "$F"

F=$(fixture)
{ grep -vF "$ARMLINE" "$ROOT/hooks/git-safety.sh"; echo "# $ARMLINE"; echo "echo '$ARMLINE'"; } > "$F/hooks/git-safety.sh"
rejects "wiring named only in a comment or a string" 'git-safety\.sh: never sources' "$F"

F=$(fixture)
awk -v arm="$ARMLINE" '$0 == arm { print "[ -n \"$INPUT\" ] || exit 0" } { print }' "$ROOT/hooks/git-safety.sh" > "$F/hooks/git-safety.sh"
rejects "a decision above the wiring" 'git-safety\.sh: line [0-9]+ can decide before' "$F"

F=$(fixture)
awk -v arm="$ARMLINE" '$0 == arm { print "if true; then " arm; print "fi"; next } { print }' "$ROOT/hooks/git-safety.sh" > "$F/hooks/git-safety.sh"
rejects "wiring only inside a branch" 'git-safety\.sh: never sources' "$F"

F=$(fixture)
{ echo '#!/bin/bash'; tail -n +2 "$ROOT/hooks/git-safety.sh"; } > "$F/hooks/git-safety.sh"
rejects "a hook run by the system bash" 'git-safety\.sh: shebang' "$F"

F=$(fixture)
grep -vx 'HOOK_FIRE_ASK=1' "$ROOT/hooks/ask-records-decision.sh" > "$F/hooks/ask-records-decision.sh"
rejects "an ask answer without the ask marker" 'ask-records-decision\.sh: prints a permissionDecision "ask" without' "$F"

# Libraries and tests are not invocations; only top-level scripts are counted.
F=$(fixture)
mkdir -p "$F/hooks/__tests__"
printf '#!/usr/bin/env bash\nexit 2\n' > "$F/hooks/lib/unwired-helper.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$F/hooks/__tests__/x.test.sh"
check_tree "$F" >/dev/null && ok || bad "a library or a test counted as a hook: $(check_tree "$F")"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]

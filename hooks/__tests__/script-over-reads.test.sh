#!/usr/bin/env bash
# script-over-reads.sh's --help hint (owner ruling 2026-10-01, restored 2026-10-15): main opened a driver's
# source dozens of times a day to learn how to call it, and each read stays in its context. A read of a
# scripts/*.sh that answers --help carries a hint to run --help instead. Advice only: it never blocks, and a
# worker's own reads get none.
set -u
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

git init -q -b main "$T/main" && git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/main" worktree add -q "$T/wt" -b work 2>/dev/null
mkdir -p "$T/p/scripts/__tests__"
printf '#!/usr/bin/env bash\ncase $1 in --help|-h) echo usage ;; esac\n' > "$T/p/scripts/drive.sh"
printf '#!/usr/bin/env bash\necho no help here\n' > "$T/p/scripts/plain.sh"
cp "$T/p/scripts/drive.sh" "$T/p/scripts/__tests__/drive.test.sh"
# read <dir> <tool> <path or command> -- the hook's exit code, then its stdout.
N=0
read_as() {
  N=$((N + 1))
  local in
  if [ "$2" = Read ]; then in=$(jq -cn --arg p "$3" --arg c "$1" '{session_id: "sor-'$$'-'$N'", cwd: $c, tool_name: "Read", tool_input: {file_path: $p}, tool_response: {}}')
  else in=$(jq -cn --arg p "$3" --arg c "$1" '{session_id: "sor-'$$'-'$N'", cwd: $c, tool_name: "Bash", tool_input: {command: $p}, tool_response: {}}'); fi
  (cd "$1" && COMMANDECK_HOOK_TIER=strict bash "$SOURCE/hooks/script-over-reads.sh" <<<"$in" 2>/dev/null; echo "rc=$?")
  rm -f "/tmp/claude-read-families-sor-$$-$N" "/tmp/claude-read-families-warned-sor-$$-$N"
}
hint() { grep -c "Hint: 'bash $T/p/scripts/drive.sh --help' prints its flags" <<<"$1"; }

OUT=$(read_as "$T/main" Read "$T/p/scripts/drive.sh")
check "main's Read of a driver that answers --help gets the hint, and passes" "1:1" "$(hint "$OUT"):$(grep -c '^rc=0$' <<<"$OUT")"
check "the hint rides as context for the model" 1 "$(grep -v '^rc=' <<<"$OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -c -- '--help')"
check "a shell read of it gets the same hint" 1 "$(hint "$(read_as "$T/main" Bash "sed -n 1,40p $T/p/scripts/drive.sh")")"
check "a script with no --help gets none" 0 "$(read_as "$T/main" Read "$T/p/scripts/plain.sh" | grep -c Hint)"
check "a test file gets none" 0 "$(read_as "$T/main" Read "$T/p/scripts/__tests__/drive.test.sh" | grep -c Hint)"
OUT=$(read_as "$T/wt" Read "$T/p/scripts/drive.sh")
check "a worker's read gets none, and passes" "0:1" "$(grep -c Hint <<<"$OUT"):$(grep -c '^rc=0$' <<<"$OUT")"
check "with strict hooks off, none" 0 "$(cd "$T/main" && jq -cn --arg p "$T/p/scripts/drive.sh" '{session_id: "sor-off", tool_name: "Read", tool_input: {file_path: $p}}' \
  | COMMANDECK_HOOK_TIER=default bash "$SOURCE/hooks/script-over-reads.sh" 2>/dev/null | grep -c Hint)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

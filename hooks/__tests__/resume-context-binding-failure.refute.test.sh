#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
box=$(mktemp -d)
trap 'rm -rf "$box"' EXIT
mkdir -p "$box/main" "$box/bin" "$box/home/.claude/checkpoints" "$box/home/.config/orca"
git -C "$box/main" init -q
PSLUG=$(printf '%s' "$(git -C "$box/main" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo
cp="$box/home/.claude/checkpoints/checkpoint.md"
mark="$box/home/.claude/checkpoints/resume-pending.$PSLUG"
echo 'resume this work' > "$cp"
echo "$cp" > "$mark"
mkdir -p "$box/home/.commandeck/scratch/$PSLUG" && echo run_test > "$box/home/.commandeck/scratch/$PSLUG/current-run"
cat > "$box/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
echo 'run-use unavailable' >&2
exit 1
EOF
chmod +x "$box/bin/orca-ide"
payload=$(printf '{"session_id":"sid-new","transcript_path":"%s/home/.claude/projects/p/sid-new.jsonl","cwd":"%s/main","hook_event_name":"SessionStart","source":"startup"}' "$box" "$box")
out=$(cd "$box/main" && printf '%s' "$payload" | PATH="$box/bin:$PATH" HOME="$box/home" \
  COMMANDECK_BOARD_CMD=true bash "$root/hooks/resume-context.sh")
[[ -f "$mark" ]] || { echo 'failed binding lost the retry marker' >&2; exit 1; }
grep -q 'NOT BOUND' <<<"$out" || { echo 'failed binding was presented as complete' >&2; exit 1; }
[[ "$(cat "$box/home/.claude/checkpoints/sid-new.resumed-from" 2>/dev/null)" = "$cp" ]] \
  || { echo 'failed binding injected the checkpoint without recording its ancestry' >&2; exit 1; }

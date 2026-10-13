#!/usr/bin/env bash
set -eu
ROOT=$(git rev-parse --show-toplevel)
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin" "$BOX/repo" "$BOX/home/.claude/checkpoints"
git -C "$BOX/repo" init -q
PSLUG=$(printf '%s' "$(git -C "$BOX/repo" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo
printf '#!/usr/bin/env bash\nexit 0\n' > "$BOX/bin/orca-ide"
chmod +x "$BOX/bin/orca-ide"
printf 'exit 0\n' > "$BOX/helper.sh"

CP="$BOX/home/.claude/checkpoints/sid.md"
printf '# First checkpoint\n' > "$CP"
touch "$CP.restarted"
printf '# Second checkpoint: new pending work\n' > "$CP"
# Model indistinguishable timestamps after a second checkpoint write.
perl -e '$n=time-60; utime($n,$n,@ARGV)' "$CP" "$CP.restarted"
touch "${CP%.md}.handoff"
printf '{}\n' > "$BOX/transcript.jsonl"

(
  cd "$BOX/repo"
  printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' \
    "$BOX/transcript.jsonl" |
    env -i PATH="$BOX/bin:$PATH" HOME="$BOX/home" \
      ORCA_TERMINAL_HANDLE=old-pane \
      COMMANDECK_RESTART_HELPER="$BOX/helper.sh" \
      bash "$ROOT/hooks/context-clear-stop.sh"
)
if [ ! -f "$BOX/home/.claude/checkpoints/resume-pending.$PSLUG" ]; then
  echo 'FAIL: second checkpoint write was mistaken for the first restart'
  exit 1
fi

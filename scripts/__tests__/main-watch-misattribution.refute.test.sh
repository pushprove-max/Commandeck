#!/usr/bin/env bash
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
T=$(mktemp -d /tmp/main-watch-refute.XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/scripts" "$T/bin" "$T/home/.config/orca" "$T/scratch" "$T/ws"
git -C "$T/repo" init -q
cp "$SOURCE/scripts/"{main-watch,paths,requirements,project-main,host-services,orca-task-create}.sh "$T/repo/scripts/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/repo/scripts/read-verdict.sh"
# The machine-wide file names another project's run: each project reads its own.
echo run_foreign > "$T/home/.config/orca/current-run"
mkdir -p "$T/scratch" && echo run_test > "$T/scratch/current-run"
: > "$T/agents"; : > "$T/tasks"; : > "$T/sends"
cat > "$T/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration task-list")
    jq -Rn '{result:{tasks:[inputs | split(" ") | {id:.[0],status:.[1]}]}}' < "$T/tasks" ;;
  "orchestration send") printf '%s\n' "\$*" >> "$T/sends"; echo '{"ok":true}' ;;
  "terminal list")
    jq -Rn '{result:{terminals:[inputs | split(" ") | {handle:.[0],tabId:.[0],leafId:"l"}]}}' < "$T/agents" ;;
  "worktree ps")
    jq -Rn '{result:{worktrees:[{agents:[inputs | split(" ") | {paneKey:(.[0]+":l"),state:.[1]}]}]}}' < "$T/agents" ;;
  *) echo '{}' ;;
esac
EOF
# No processes: the broker reaper must never see or signal this machine's own.
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ps"
chmod +x "$T/bin/"*
tick() {
  (cd "$T/repo" && PATH="$T/bin:$PATH" HOME="$T/home" \
    COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_WORKSPACES="$T/ws" \
    COMMANDECK_NOW="$1" bash scripts/main-watch.sh --once)
}
seat() {
  mkdir -p "$T/ws/$1/.claude/briefs"
  printf 'handle=%s\ntask=%s\nrole=implementer\nunit=%s\nlaunched=1000\n' \
    "$2" "$3" "$1" > "$T/scratch/seat-$1-implementer.txt"
  echo "$3 running" >> "$T/tasks"
}
seat local-again term_local task_local
echo run_old > "$T/scratch/origin-local-again.run"
echo 'term_local working' > "$T/agents"; tick 2000
echo 'term_local done' > "$T/agents"; tick 2060
grep -q 'local-again' "$T/sends" ||
  { echo 'FAIL: stale peer origin suppressed a local finish'; exit 1; }

seat shared-result term_silent task_silent
echo 'term_silent working' > "$T/agents"; tick 3000
echo 'VERDICT: GO' > "$T/ws/shared-result/.claude/briefs/other-seat-review.md"
echo 'term_silent done' > "$T/agents"; tick 3060
grep -q 'shared-result implementer stopped without reporting; inspect' "$T/sends" ||
  { echo 'FAIL: another seat’s verdict made a silent seat look finished'; exit 1; }

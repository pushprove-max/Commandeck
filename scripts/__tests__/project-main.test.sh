#!/usr/bin/env bash
# project-main.test.sh -- a Builder works in a linked worktree and controls its
# own shell. COMMANDECK_MAIN and COMMANDECK_WORKSPACES are followed there only
# for a fixture under the temp folder, so a Builder cannot point the plugin's
# scripts at a checkout of its choosing. What this pins: Git's own routing
# variables do not hide the worktree from that rule, and a stand-in project is
# never paired with a worktrees folder outside the temp folder.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

for p in one samename/one; do
  mkdir -p "$T/$p" && git init -q -b main "$T/$p" && git -C "$T/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
done
U=$T/ws/unit; git -C "$T/one" worktree add -q "$U" -b unit
# resolve <env assignments...>: PP_MAIN and PP_WORKSPACES as the Builder in $U gets them.
resolve() { ( cd "$U" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u COMMANDECK_WORKSPACES "$@" bash -c '. "$0" && pp_main_resolve && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/project-main.sh" ); }

check "GIT_DIR naming main's git folder does not let the Builder name its own tree" "$T/one" \
  "$(resolve GIT_DIR="$(git -C "$U" rev-parse --path-format=absolute --git-common-dir)" COMMANDECK_MAIN="$U" COMMANDECK_WORKSPACES="$U" | cut -d' ' -f1)"
# A home outside the temp folder, as a real one is: the stand-in's default worktrees
# folder is then a real project's of the same name. Fixed, so a runner's HOME under temp cannot change it.
check "a stand-in project is not paired with a real project's worktrees folder of the same name" "$T/one" \
  "$(resolve HOME=/nonexistent-home COMMANDECK_MAIN="$T/samename/one" | cut -d' ' -f1)"
check "a stand-in project with its worktrees folder under the temp folder is followed" "$T/samename/one $T/home/orca/workspaces/one" \
  "$(resolve HOME="$T/home" COMMANDECK_MAIN="$T/samename/one")"
# Consumers compare "$PP_WORKSPACES/..." as text with the paths Orca and the transcripts
# report: a trailing / or /. left in it made that "//" or "/./" and matched nothing. Nothing
# else is respelled (a link or .. too), or Orca's spelling of the same folder stops matching.
# COMMANDECK_MAIN is kept as given: the install manifest and the scratch folder are keyed by it.
spell() { ( cd "$T/one" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$1" COMMANDECK_WORKSPACES="$2" bash -c '. "$0" && pp_main_resolve && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/project-main.sh" ); }
ln -s "$T" "$T/link"
check "trailing slashes on the worktrees folder are dropped, COMMANDECK_MAIN's are kept" "$T/one/ $T/ws" "$(spell "$T/one/" "$T/ws//")"
check "a trailing /. on the worktrees folder is dropped, COMMANDECK_MAIN's is kept" "$T/one/. $T/ws" "$(spell "$T/one/." "$T/ws/./")"
check "a link's spelling of both is kept" "$T/link/one $T/link/ws" "$(spell "$T/link/one" "$T/link/ws")"

# #99: builder-launch.sh branches only from a main fast-forwarded from origin (pp_sync_main);
# a release marked published on origin and not fetched was rebuilt as a draft.
O=$T/one
git clone -q --bare "$O" "$T/origin.git"; git -C "$O" remote add origin "$T/origin.git"; git clone -q "$T/origin.git" "$T/other"
push() { git -C "$T/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$T/other" push -q origin HEAD:main; }
sync() { ( cd "$O" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES COMMANDECK_MAIN="$O" bash -c '. "$0" && pp_sync_main "$@"' "$REAL/scripts/paths.sh" "$O" "$@" 2>&1; echo "rc=$?" ); }
push "release: mark published"
check "--check with origin ahead moves nothing" "rc=0 first" "$(sync --check) $(git -C "$O" log -1 --format=%s main)"
check "with origin ahead, main is fast-forwarded" "rc=0 release: mark published" "$(sync) $(git -C "$O" log -1 --format=%s main)"
push "release: next"; git -C "$O" checkout -q -b off
check "off main, the main branch itself is fast-forwarded" "rc=0 release: next" "$(sync) $(git -C "$O" log -1 --format=%s main)"
git -C "$O" checkout -q main; git -C "$O" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "local only"; push "release: third"
check "a diverged main refuses with the reason" "1 rc=1 local only" "$(sync | grep -c 'cannot fast-forward') $(sync | tail -1) $(git -C "$O" log -1 --format=%s main)"

# Issue 395: paths.sh sourced from zsh failed lines later with a parse error; another shell is refused at its first line.
NB=$(command -v zsh || command -v dash)
out=$(cd "$T" && "$NB" -c '. "$0"' "$REAL/scripts/paths.sh" 2>&1); rc=$?
check "sourced from a non-bash shell" "rc=1 paths.sh: source this from bash; this shell is not bash" "rc=$rc $out"

# No script removes a main checkout. dashboard.sh --project took the folder it was handed as its run folder
# before its DASH_NOW check, and the exit trap then ran rm -rf on it: typed by hand with no DASH_NOW,
# `dashboard.sh --project ~/repos/commandeck` removed the whole main checkout (2026-10-15).
V=$T/victim; mkdir -p "$V" "$T/home" && git init -q -b main "$V" && git -C "$V" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
( cd "$V" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u DASH_NOW HOME="$T/home" COMMANDECK_MAIN="$V" timeout 20 bash "$REAL/scripts/dashboard.sh" --project "$V" >/dev/null 2>&1 )
check "dashboard.sh --project handed the main checkout, with no DASH_NOW, leaves it in place" yes "$([ -d "$V/.git" ] && echo yes)"
# pp_rm_rf is the one recursive removal of the scripts that read paths.sh: it removes nothing when any path it is
# given is a main checkout, a git folder, a folder holding the project's checkout, HOME or /.
mkdir -p "$V/nest" && git init -q -b main "$V/nest/proj" && git -C "$V/nest/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
rmrf() { ( cd "$V/nest/proj" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES HOME="$T/home" COMMANDECK_MAIN="$V/nest/proj" bash -c '. "$0" && pp_rm_rf "$@"' "$REAL/scripts/paths.sh" "$@" >/dev/null 2>&1; echo "rc=$?" ); }
ln -s "$V" "$T/vlink"
# Git data at any depth too: COMMANDECK_SCRATCH=<main>/.git/objects made uninstall --delete-data take the history
# (pass 1). Also a file in a git folder, a linked worktree's .git file, a bare repository and a path inside it, and
# a folder that holds some other checkout or bare repository deeper down.
git init -q --bare "$T/bare.git"; mkdir -p "$T/holds/a/b" && git init -q "$T/holds/a/b/repo"; mkdir -p "$T/holdsbare/x" && git init -q --bare "$T/holdsbare/x/y.git"
# A bare repository is known by what it holds, not by its name (pass 2: a bare backup named "backup").
mkdir -p "$T/holdsplain/x" && git init -q --bare "$T/holdsplain/x/backup"
git -C "$V/nest/proj" worktree add -q --detach "$T/linked" 2>/dev/null
n=0
for p in "$V/nest/proj" "$T/vlink/nest/proj/." "$V/nest" "$V/nest/proj/.git" "$V" "$T/home" \
  "$V/nest/proj/.git/objects" "$V/nest/proj/.git/HEAD" "$T/linked/.git" "$T/bare.git" "$T/bare.git/objects" "$T/holds" "$T/holdsbare" \
  "$T/holdsplain" "$T/holdsplain/x/backup/objects"; do
  n=$((n + 1)); mkdir -p "$T/junk$n"
  check "pp_rm_rf refuses $p and removes nothing, the other path either ($n)" "rc=1 kept kept kept" \
    "$(rmrf "$T/junk$n" "$p") $([ -d "$T/junk$n" ] && echo kept) $([ -d "$V/nest/proj/.git" ] && [ -d "$V/.git" ] && echo kept) $([ -e "$p" ] && echo kept)"
done
# Nothing in the caller's environment changes the answer: git's routing and discovery variables (pass 2:
# GIT_CEILING_DIRECTORIES naming the git folder hid it from git), and a PATH with no git on it.
for e in "GIT_DIR=$T/bare.git" "GIT_WORK_TREE=$T" "GIT_CEILING_DIRECTORIES=$V/nest/proj/.git" \
  "GIT_CEILING_DIRECTORIES=$T/holdsplain/x/backup" "GIT_DISCOVERY_ACROSS_FILESYSTEM=0"; do
  check "pp_rm_rf refuses git data with $e in the caller's environment" "rc=1 kept kept" \
    "$(export "$e"; rmrf "$V/nest/proj/.git/objects" "$T/holdsplain/x/backup/objects") $([ -d "$V/nest/proj/.git/objects" ] && echo kept) $([ -d "$T/holdsplain/x/backup/objects" ] && echo kept)"
done
mkdir -p "$T/junk/a" "$V/nest/proj/.claude/metrics"; : > "$T/junk-file"; : > "$V/nest/proj/.claude/metrics/decisions.jsonl"
check "pp_rm_rf removes a plain folder, a file, and a file in a checkout's work tree (uninstall's metrics)" "rc=0 gone" \
  "$(rmrf "$T/junk" "$T/junk-file" "$V/nest/proj/.claude/metrics/decisions.jsonl") $([ -e "$T/junk" ] || [ -e "$T/junk-file" ] || [ -e "$V/nest/proj/.claude/metrics/decisions.jsonl" ] || echo gone)"
# Every other raw rm -rf removes a folder its own script made with mktemp; a new one is read here before it ships.
check "only the scripts that remove their own mktemp folder use a raw rm -rf" \
  "scripts/context-overhead.sh scripts/hook-probe.sh scripts/paths.sh scripts/peer-offload.sh scripts/proof-run.sh scripts/ruling-log-archive.sh scripts/run-shell-tests.sh scripts/startup-size.sh scripts/update.sh" \
  "$(cd "$REAL" && grep -lE 'rm -(rf|fr|r) ' hooks/*.sh hooks/lib/*.sh scripts/*.sh | while read -r f; do grep -E 'rm -(rf|fr|r) ' "$f" | grep -qv 'pp_rm_rf\|^[[:space:]]*#\|warn "running state' && echo "$f"; done | sort | paste -sd' ' -)"

# COMMANDECK_MAIN is kept as given and a worktrees folder loses only a trailing / or /., so each compare
# with a path Orca, a transcript or a record reports puts both sides through one rule, in Bash and in jq alike.
pm() { bash -c '. "$0"; "$@"' "$REAL/scripts/project-main.sh" "$@"; }
while IFS='|' read -r in want; do
  check "pp_norm and jq's pnorm both spell [$in] as [$want]" "$want $want" \
    "$(pm pp_norm "$in") $(bash -c '. "$0"; jq -nr --arg p "$1" "$PP_PNORM \$p | pnorm"' "$REAL/scripts/project-main.sh" "$in")"
done <<'EOF2'
/a/|/a
/a/.|/a
/a//b/./c/.|/a/b/c
/a/././b|/a/b
//|/
/x y/./z//|/x y/z
/a/.b/..|/a/.b/..
EOF2
mkdir -p "$T/home/.commandeck/dashboard" "$T/bin"; printf '%s\n' "$T/elsewhere" "$V" > "$T/home/.commandeck/dashboard/projects"
cat > "$T/bin/orca-ide" <<EOF2
#!/usr/bin/env bash
[ -e "$T/list-by-id" ] && echo '{"result":{"terminals":[{"handle":"h-id","worktreeId":"wt1::$V/","agentIdentity":"claude"}]}}' \
  || echo '{"result":{"terminals":[{"handle":"h-main","worktreePath":"$V","agentIdentity":"claude"}]}}'
EOF2
chmod +x "$T/bin/orca-ide"
pths() { ( cd "$V" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$1" bash -c '. "$0" && eval "$1"' "$REAL/scripts/paths.sh" "$2" 2>/dev/null ); }
check "a main checkout given as <tmp>/victim/./ is the one the dashboard registry names, and the one Orca's pane is in" "yes h-main" \
  "$(pths "$V/./" 'pp_registered && echo yes') $(pths "$V/./" 'pp_pane_of "$PP_MAIN"')"
check "another checkout is neither" "no" "$(pths "$V/nest/proj" 'pp_registered && echo yes || echo no; pp_pane_of "$PP_MAIN"')"
# Orca may name the worktree only in worktreeId: the pane is still found (wtp), and still not for another checkout.
touch "$T/list-by-id"
check "a pane named by worktreeId alone is main's pane, and not another checkout's" "h-id|" \
  "$(pths "$V" 'pp_pane_of "$PP_MAIN"')|$(pths "$V/nest/proj" 'pp_pane_of "$PP_MAIN"')"
rm -f "$T/list-by-id"

# Claude Code gives a Bash command no CLAUDE_PROJECT_DIR, so main closing a
# task (orca-wait.sh --close) from a folder outside the project was told "no
# project here ... is a git checkout". With nothing else naming the project, the
# Orca pane's own worktree does; a worktree pane's still resolves to its main.
mkdir -p "$T/elsewhere" "$T/obin"
# The list holds term_m with only its worktreeId: issue 161's shape, an entry with no worktreePath.
printf '#!/usr/bin/env bash\necho "$*" >> %q\ncase "$*" in *"terminal list"*) jq -nc --arg w "id::%s" %s ;; *) echo %s ;; esac\n' \
  "$T/orca.log" "$T/one" "'{ok: true, result: {terminals: [{handle: \"term_m\", worktreeId: \$w}]}}'" "'{\"ok\":true}'" > "$T/obin/orca-ide"; chmod +x "$T/obin/orca-ide"
away() { ( cd "$T/elsewhere" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u COMMANDECK_WORKSPACES -u ORCA_TERMINAL_HANDLE PATH="$T/obin:$PATH" COMMANDECK_SCRATCH="$T/scratch" "$@" ); }
check "main closes a task from outside the checkout, its pane's worktree naming the project" "closed task_1:1" \
  "$(away ORCA_WORKTREE_ID="id-1::$T/one" bash "$REAL/scripts/orca-wait.sh" --close task_1 2>&1):$(grep -c 'task-update --id task_1 --status completed' "$T/orca.log" 2>/dev/null)"
check "a worktree pane's resolves to its main checkout" "$T/one" \
  "$(away ORCA_WORKTREE_ID="id-2::$U" bash -c '. "$0" && pp_main_resolve && printf "%s" "$PP_MAIN"' "$REAL/scripts/project-main.sh")"
check "with no worktree id, Orca's list entry for this pane's handle names the project (issue 161)" "closed task_3:1" \
  "$(away ORCA_WORKTREE_ID= ORCA_TERMINAL_HANDLE=term_m bash "$REAL/scripts/orca-wait.sh" --close task_3 2>&1):$(grep -c 'task-update --id task_3 --status completed' "$T/orca.log" 2>/dev/null)"
check "with no pane either, it still says there is no project, and names where it looked" 1 \
  "$(away ORCA_WORKTREE_ID= bash "$REAL/scripts/orca-wait.sh" --close task_2 2>&1 | grep -c "no project here: .*tried: $T/elsewhere)")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

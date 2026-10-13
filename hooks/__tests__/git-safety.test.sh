#!/usr/bin/env bash
# Self-test for git-safety.sh.
#
# Three defects it pins:
#  1. The hook tested `^git ` -- the command's PREFIX. `cd x && git push
#     --force`, `FOO=1 git push --force` and a `git` call after a `;` never
#     reached one check, which is most of the ways a dangerous git command is
#     actually typed.
#  2. Its `--force` pattern also matched `--force-with-lease`, the safe form the
#     hook's OWN message recommends. It blocked the push it told you to use.
#  3. Widening the entry gate was not enough: each individual check still
#     demanded `git` immediately followed by its subcommand, so an option in
#     between defeated it. `git -C <path>` is this repo's own standard idiom.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/git-safety.sh"
PASS=0 FAIL=0

# The file runs itself once per part, side by side, and prints the parts in
# order (the way bash-guardrails.test.sh does): a hook call costs about
# 80 ms and there are some 340. Every line runs in every part, so each part has
# every helper; outside its own part `run` starts nothing and `check` records
# nothing. One part alone: GIT_SAFETY_TEST_PART=<n> in front.
PARTS=4
if [ -z "${GIT_SAFETY_TEST_PART:-}" ]; then
  OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
  for P in $(seq "$PARTS"); do GIT_SAFETY_TEST_PART=$P bash "$0" > "$OUT/$P" 2>&1 & done
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
case "$GIT_SAFETY_TEST_PART" in [1-$PARTS]) ;; *) echo "FAIL no such part: $GIT_SAFETY_TEST_PART (parts: 1 to $PARTS)" >&2; exit 2 ;; esac
part() { if [ "$1" = "$GIT_SAFETY_TEST_PART" ]; then ON=1; else ON=0; fi; }

check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
cmd() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
run() { [ "$ON" = 1 ] || return 0; bash "$HOOK" >/dev/null 2>&1 <<<"$(cmd "$1")"; echo $?; }

part 1
# --- 1. a git call anywhere in the command is screened ------------------------
check "a bare force push blocks"                2 "$(run 'git push --force origin main')"
check "a force push after && blocks"            2 "$(run 'cd /repo && git push --force origin main')"
check "a force push after ; blocks"             2 "$(run 'npm test ; git push --force')"
check "a force push after | blocks"             2 "$(run 'true | git push --force')"
# A push's arguments end at a command separator: the next command's -f is its own.
check "a push, then a search with -f, passes"   0 "$(run 'git push origin HEAD && rg -f patterns.txt src/')"
check "a push, then a word --force, passes"     0 "$(run 'git push origin HEAD; echo --force')"
check "a push with -f after its refspec blocks" 2 "$(run 'git push origin main -f')"
# A quoted word is still the word git gets: only quoted TEXT is not a command.
check "a quoted --force blocks"                 2 "$(run "git push '--force' origin main")"
check "a double-quoted --hard blocks"           2 "$(run 'git reset "--hard" HEAD~1')"
check "a quoted subcommand blocks"              2 "$(run "git 'push' --force")"
# The same word after git's own options, after a quoted option value, in
# halves, and with git itself quoted: bash hands git the same words each time.
check "a quoted subcommand after -C blocks"     2 "$(run "git -C /repo 'push' --force")"
check "a double-quoted reset after -C blocks"   2 "$(run 'git -C /repo "reset" --hard HEAD')"
check "after a quoted option value it blocks"   2 "$(run "git -C '/my repo' 'push' --force")"
check "a subcommand quoted in halves blocks"    2 "$(run "git pu'sh' --force")"
check "a backslash inside the subcommand blocks" 2 "$(run 'git -C /repo p\ush --force')"
check "a dollar-quoted subcommand blocks"       2 "$(run "git -C /repo \$'push' --force")"
check "a backslash inside clean blocks"          2 "$(run 'git -C /repo cl\ean -fd')"
check "a dollar-quoted stash drop blocks"       2 "$(run "git -C /repo \$'stash' drop")"
check "a quoted git blocks"                   2 "$(run "'git' push --force")"
check "a quoted word in a commit message is still a message" 0 "$(run "git commit -m 'push'")"
check "a commit message that is one flag passes" 0 "$(run "git commit -m '--force'")"
check "a message naming a flag passes"          0 "$(run 'git commit -m "undo the reset --hard" && git push origin HEAD')"
check "a force push with an env prefix blocks"  2 "$(run 'FOO=1 git push --force origin main')"
check "a force push by absolute path blocks"    2 "$(run '/usr/bin/git push --force origin main')"
check "git push -f blocks"                      2 "$(run 'git push -f origin main')"
check "git push -f after && blocks"             2 "$(run 'cd /repo && git push -f')"
check "a reset --hard after && blocks"          2 "$(run 'cd /repo && git reset --hard origin/main')"

# --- 1b. options between the verb and its subcommand --------------------------
# `git -C <path>` is how this repo types git: main types it in every worktree command. Each check demanded
# `git` immediately followed by its subcommand, so every one of these passed.
check "git -C <path> push --force blocks"       2 "$(run 'git -C /home/me/repos/some-project push --force')"
check "git --no-pager push --force blocks"      2 "$(run 'git --no-pager push --force')"
check "git -C <path> reset --hard blocks"       2 "$(run 'git -C /repo reset --hard origin/main')"
check "git -c k=v push --force blocks"          2 "$(run 'git -c core.pager=cat push --force')"
check "two options before push blocks"          2 "$(run 'git --no-pager -C /repo push --force')"
check "git -C <path> push -f blocks"            2 "$(run 'git -C /repo push -f')"

# --- 1d. the other force and delete forms ----------------------------
check "git push -fu blocks"                     2 "$(run 'git push -fu origin main')"
check "git push -uf blocks"                     2 "$(run 'git push -uf origin main')"
check "a +refspec blocks"                       2 "$(run 'git push origin +main')"
check "a +src:dst refspec blocks"               2 "$(run 'git -C /repo push origin +HEAD:main')"
check "an empty-source :ref refspec blocks"     2 "$(run 'git push origin :main')"
check "git push --delete blocks"                2 "$(run 'git push --delete origin feature')"
check "git push origin --delete blocks"         2 "$(run 'cd /repo && git push origin --delete feature')"
check "git push -d blocks"                      2 "$(run 'git push -d origin feature')"
check "git push --mirror blocks"                2 "$(run 'git push --mirror origin')"
check "git push -u origin <branch> passes"      0 "$(run 'git push -u origin builder/some-unit')"
check "a src:dst refspec passes"                0 "$(run 'git push origin HEAD:refs/heads/feature')"
check "a + after the push command passes"       0 "$(run 'git push origin main && echo +1')"

# --- 1c. the repository-name blanket is gone ----------------------------------
# The guard refused any command whose text contained `sister-repo`, including
# a read-only clone or a remote listing. It kept out no destructive operation
# the force/reset checks do not already cover.
check "a sister-repo remote passes"           0 \
  "$(run "git remote add poc 'git@gh:x/sister-repo.git'")"
check "cloning sister-repo passes"            0 \
  "$(run 'cd /tmp && git clone sister-repo')"
check "a force push INTO sister-repo still blocks" 2 \
  "$(run 'git push --force poc main')"

# --- 2. --force-with-lease is the RECOMMENDED form and must pass --------------
check "--force-with-lease passes"               0 "$(run 'git push --force-with-lease origin main')"
check "--force-with-lease=ref passes"           0 "$(run 'git push --force-with-lease=main:abc123 origin main')"
check "--force-with-lease after && passes"      0 "$(run 'cd /repo && git push --force-with-lease')"
check "--force-if-includes passes"              0 "$(run 'git push --force-with-lease --force-if-includes')"
check "the message still recommends the lease form" 0 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git push --force')" | grep -qF -- '--force-with-lease' && echo 0 || echo 1)"

# --- ordinary work is untouched ----------------------------------------------
check "an ordinary push passes"                 0 "$(run 'git push origin main')"
check "an ordinary git -C push passes"          0 "$(run 'git -C /repo push origin main')"
check "a plain status passes"                   0 "$(run 'git status --porcelain')"
# A subcommand is not an option, so the option group cannot swallow `log` and
# reach a later word. This is the over-match the widened pattern must not have.
check "git log with a ref named push passes"    0 "$(run 'git log --oneline push')"
check "git -C <path> status passes"             0 "$(run 'git -C /repo status')"
check "git -C <path> --force-with-lease passes" 0 "$(run 'git -C /repo push --force-with-lease')"
check "a non-git command passes"                0 "$(run 'npm run test:guards')"
check "a soft reset passes"                     0 "$(run 'git reset --soft HEAD~1')"
# git takes the flag anywhere among the arguments; the discard is the same.
check "reset --hard after the revision blocks"  2 "$(run 'git reset HEAD --hard')"
# The shell runs a quoted program name like a bare one.
check "reset --hard with git itself in quotes blocks" 2 "$(run '"git" "reset" --hard')"
check "after && too" 2 "$(run 'cd /repo && "git" reset --hard')"
check "a quoted git as an argument is still data" 0 "$(run 'git grep "git" -- "restore"')"
# The reset check reads a quoted plain word as its word, wherever it stands.
check "behind an assignment it blocks" 2 "$(run 'FOO=1 "git" "reset" --hard')"
check "behind env with an option and an assignment it blocks" 2 "$(run 'env -i FOO=1 "git" reset --hard')"
check "behind env with an option whose value is the word git it blocks" 2 "$(run 'env -u git "git" reset --hard')"
check "behind a variable set to git it blocks" 2 "$(run 'TOOL=git "git" reset --hard')"
check "run by git bisect it blocks" 2 "$(run 'git bisect run "git" reset --hard')"
check "after then it blocks" 2 "$(run 'if true; then "git" reset --hard; fi')"
check "inside braces it blocks" 2 "$(run '{ "git" reset --hard; }')"
check "a force push by a quoted git behind env blocks" 2 "$(run 'env "git" push --force')"
# A reset named in backticks inside a quoted message is refused: quotes do not
# say which backtick text is data. Put the message in a file (git commit -F).
check "backticks in single quotes are refused" 2 "$(run "git commit -m 'about \`git reset --hard\`'")"
check "an escaped backtick in double quotes is refused too" 2 "$(run 'git commit -m "about \`git reset --hard\`"')"
# The cost: a quoted git that is only data blocks like its unquoted form when
# a hard reset follows it.
check "echo of a quoted git and a hard reset blocks, as unquoted" "2 2" "$(run 'echo "git" reset --hard') $(run 'echo git reset --hard')"
check "printf of a quoted git and a hard reset blocks" 2 "$(run 'printf "%s\n" "git" reset --hard')"
check "a quoted git with no discarding form after it passes" "0 0 0" "$(run 'grep -rn "git" scripts') $(run 'git config user.name "git"') $(run 'cd "git" && git status')"
check "reset -q --hard blocks"                  2 "$(run 'git reset -q --hard')"
check "a --hard in the next command is not this reset's" 0 "$(run 'git reset --soft HEAD~1; echo --hard')"
check "an ordinary push is SILENT"              "" "$(bash "$HOOK" 2>&1 <<<"$(cmd 'git push origin main')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- quoted text is not a command --------------------------------------------
# A commit message or an echo that NAMES a dangerous operation must not block.
# Learned the hard way: every commit message mentioning a protected file used
# to be refused.
check "a commit message naming a force push passes" 0 \
  "$(run "git commit -m 'never run git push --force here'")"
check "an echo naming a force push passes"          0 \
  "$(run 'echo "do not use git push --force"')"

# --- multi-line messages are data too ---------------------------------
# The quote strip ran line by line, so a quote or heredoc spanning lines was
# never stripped and the repo's standard heredoc commit form blocked.
check "a heredoc commit message naming reset --hard passes" 0 \
  "$(run $'git commit -m "$(cat <<\'EOF\'\nfix: stop using git reset --hard here\nEOF\n)"')"
check "a two-line quoted message naming a force push passes" 0 \
  "$(run $'git commit -m "first line\nnever git push --force"')"
check "commit -F - with a heredoc naming push -f passes" 0 \
  "$(run $'git commit -F - <<EOF\nwhy we never git push -f origin main\nEOF')"
check "a real force push after a heredoc commit still blocks" 2 \
  "$(run $'git commit -F - <<EOF\nmsg\nEOF\ngit push --force')"
# A heredoc ends on the line bash ends it on: an indented look-alike of the end
# word is still body, and an apostrophe after it must not swallow the push.
check "a force push after a heredoc holding an indented look-alike of its end word still blocks" 2 \
  "$(run $'cat <<\'EOF\'\n  EOF\nIt\'s\nEOF\ngit push --force')"
check "the same with a tab, which ends a heredoc only under <<-" 2 \
  "$(run $'cat <<\'EOF\'\n\tEOF\nIt\'s\nEOF\ngit push --force')"
check "under <<- a tabbed end word ends the heredoc and the push after it blocks" 2 \
  "$(run $'cat <<-\'EOF\'\n\tIt\'s\n\tEOF\ngit push --force')"
check "under <<- a heredoc naming push -f still passes" 0 \
  "$(run $'cat <<-\'EOF\'\n\twhy we never git push -f origin main\n\tEOF')"
# An end word that is not plain is refused before any rule reads it, here as in
# bash-guardrails.sh (which a project runs only on the strict tier). Every form
# that once hid a force push after the note:
for E in "<<'END NOTE'" "<<E'OF'" "<<'E'OF" '<<"E""OF"' "<<E\\OF" "<<'END'\\ NOTE" '<<"E\"OF"'; do
  check "a force push after a heredoc with the end word $E is refused" 2 \
    "$(run "$(printf 'cat %s\nmsg\nEOF\ngit push --force' "$E")")"
done
check "a real reset --hard inside \$(...) in quotes still blocks" 2 \
  "$(run 'echo "$(git reset --hard HEAD)"')"
check "an empty quote inside push does not dodge the prefilter" 2 \
  "$(run "git pu''sh --force")"
# Without its strip helper the hook must refuse, not read an empty command.
LONE=$(mktemp -d); cp "$HOOK" "$LONE/"
check "a missing strip-quoted.sh blocks"        2 \
  "$(bash "$LONE/git-safety.sh" >/dev/null 2>&1 <<<"$(cmd 'git push --force')"; echo $?)"
rm -rf "$LONE"

part 2
# --- 3. the other ways to discard work ---------------------------------
# reset --hard was the only discard this hook knew. Each family below throws
# away uncommitted edits, untracked files, a stash, an unmerged branch or the
# reflog that would recover them, and each sits beside ordinary work that must
# keep passing: a branch checkout is not a path checkout. Every family runs
# bare and behind a `git -C` / `git -c` option. Payloads are only screened,
# never run.
blocks() { for C in "$@"; do check "blocks: $C" 2 "$(run "$C")"; done; }
passes() { for C in "$@"; do check "passes: $C" 0 "$(run "$C")"; done; }
blocks 'git checkout -- .' 'git checkout .' 'git checkout HEAD -- src/x.ts' \
  'git -C /repo checkout -- .' 'git -c core.pager=cat checkout .' 'git checkout -- "my file.txt"'
# A forced switch throws away the uncommitted edits it would otherwise stop for.
blocks 'git checkout -f feature' 'git checkout --force main' 'git switch -f main' 'git switch --discard-changes main' \
  'git -C /repo switch --force main' 'git checkout -qf main'
passes 'git switch feature' 'git switch -c builder/new-unit' 'git switch --detach abc1234'
# The `--` is optional to git: a commit and then paths restores those paths.
blocks 'git checkout HEAD src/file.ts' 'git checkout main a.txt b.txt' 'git -C /repo checkout HEAD~1 "my file"' \
  'git checkout -q HEAD src/file.ts' 'git checkout --ours a.txt b.txt'
# One word is a branch unless it names a file here and no commit: then git restores the file.
CO=$(mktemp -d); git -C "$CO" init -q -b main; echo x > "$CO/notes.txt"; mkdir "$CO/docs"
git -C "$CO" -c user.name=t -c user.email=t@t add -A; git -C "$CO" -c user.name=t -c user.email=t@t commit -qm x; git -C "$CO" branch docs
at() { jq -cn --arg c "$2" --arg d "$1" '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>&1; echo $?; }
check "a checkout of one existing file blocks"              2 "$(at "$CO" 'git checkout notes.txt')"
check "a branch named like a folder is still a branch"      0 "$(at "$CO" 'git checkout docs')"
check "a word that is neither file nor commit passes"       0 "$(at "$CO" 'git checkout feature')"
rm -rf "$CO"
passes 'git checkout -b new origin/main' 'git checkout -B unit start' 'git checkout --orphan fresh start' \
  'git checkout -b new --track origin/main' 'git checkout --detach HEAD~1' 'git checkout -t origin/x'
passes 'git checkout feature' 'git checkout -q --detach abc1234' 'git checkout -b builder/new-unit' \
  'git -C /repo checkout feature' 'git --no-pager checkout feature'
blocks 'git restore .' 'git restore --worktree src/x.ts' 'git restore --staged --worktree src/x.ts' \
  'git restore -SW src/x.ts' 'git -C /repo restore .' 'git restore "my file.txt"'
passes 'git restore --staged src/x.ts' 'git restore -S src/x.ts' 'git -C /repo restore --staged "my file.txt"'
blocks 'git clean -fdx' 'git clean -xdf' 'git clean --force -d' 'git clean -d --force' 'git -C /repo clean -fd'
passes 'git clean -ndx' 'git clean -nfdx' 'git clean --dry-run -fdx' 'git -C /repo clean -n'
blocks 'git stash drop' 'git stash drop stash@{0}' 'git stash clear' 'git -C /repo stash drop'
passes 'git stash list' 'git stash show' 'git stash show -p stash@{0}' 'git -C /repo stash list'
blocks 'git branch -D feature' 'git branch --delete --force feature' 'git branch --force --delete feature' \
  'git branch -d -f feature' 'git -c advice.detachedHead=false branch -D feature'
passes 'git branch -d merged' 'git branch --list' 'git branch --show-current' 'git -C /repo branch -d merged'
blocks 'git worktree remove --force /tmp/wt' 'git worktree remove -f /tmp/wt' \
  'git worktree remove /tmp/wt --force' 'git -C /repo worktree remove --force /tmp/wt'
passes 'git worktree list' 'git worktree remove /tmp/wt' 'git -C /repo worktree list'
blocks 'git reflog expire --expire=now --all' 'git reflog expire --all' \
  'git -C /repo reflog expire --expire-unreachable=now --all'
passes 'git reflog' 'git reflog show' 'git -C /repo reflog show'
blocks 'git gc --prune=now' 'git gc --aggressive --prune=now' 'git -C /repo gc --prune=now'
passes 'git gc' 'git gc --no-prune' 'git -C /repo gc'
# Each git call is judged on its own arguments, wherever it sits in the command.
blocks 'cd /repo && git checkout -- . ; echo "done"' 'FOO=1 git clean -fdx' 'npm test || git stash drop' \
  'echo "$(git restore .)"' '/usr/bin/git branch -D feature' $'git status\ngit clean -fdx'
passes "git commit -m 'never run git clean -fdx or git checkout -- . here'" \
  'git status; echo "git stash clear"' 'git checkout feature; echo -- .' 'git branch --list && rm -f x' \
  'git worktree list | grep -- --force' $'git commit -F - <<EOF\nwhy we never git branch -D or git gc --prune=now\nEOF'
# The integration scripts run restore, checkout and worktree cleanup inside
# themselves; the hook sees the submitted command, which names no git call.
passes 'bash scripts/merge-unit-local.sh unit --dry-run'
# A quoted argument is still an argument. Quoted spans were removed outright,
# so `git -C "/repo" clean -fdx` lost the option's value, the option took
# `clean` as its value instead, and the discard passed. A quoted span that is
# one plain token is the word bash passes; quoted prose is still data. The two
# reported inputs are pinned in git-safety-quoted-options.refute.test.sh.
blocks 'git -C "/repo" clean -fdx' 'git -c "core.pager=cat" clean -fdx' "git -C '/repo' stash drop" \
  'git -C "/my repo" clean -fdx' 'git --git-dir "/repo/.git" branch -D feature' \
  'git clean "-fdx"' 'git checkout "."' 'git "clean" -fdx' 'git cl"ea"n -fdx' 'git stash "drop"' \
  'git -C "$(pwd)" clean -fdx'
passes 'git -C "/repo" checkout feature' 'git -c "core.pager=cat" stash list' 'git -C "/my repo" clean -n' \
  'git -C "/repo" branch -d "merged"' 'git checkout "feature"' \
  "git -C \"/repo\" commit -m 'never run git clean -fdx here'" 'git commit -m "clean" -m "-fdx"'
# Everything after `--` is a path, quoted or not: a file named -n is not a dry
# run and a file named --staged does not make a restore index-only.
blocks 'git clean -f -- "-n"' 'git clean -f -- -n' 'git restore -- "--staged"' 'git restore -- --staged'
passes 'git clean -n -- "-f"' 'git restore --staged -- "src/x.ts"'
# Quoted data is never the start of a git call, and a bare `--` is not a git
# option, so a search term or a file name cannot read as a second invocation.
passes 'git grep -n "git" -- "restore"' 'git grep -n git -- restore' 'git log --grep "git" -- "stash" "drop"' \
  'git restore-mtime' 'git clean-merged -f'
check "a discard refusal says what was refused" 1 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git clean -fdx')" | grep -c 'git clean')"

part 3
# --- 4. a quoted subcommand is still the subcommand --------------------
# The force-push and hard-reset checks read the command with every quoted span
# removed, so `git -C /repo 'push' --force` had no subcommand left to match and
# passed. Bash runs it exactly as the unquoted form.
blocks "git -C /repo 'push' --force" 'git -C /repo "reset" --hard' "git 'push' --force origin main" \
  'git "reset" --hard HEAD' 'git -C /repo "push" -f' 'git -C "/repo" pu"sh" origin +main' \
  'git --no-pager "push" --mirror' 'git -C /repo "push" origin --delete feature' 'git push "--force" origin main' \
  'git reset "--hard"'
# Every other destructive form, quoted, with and without a global option.
blocks 'git "clean" -fdx' 'git -C /repo "clean" -fdx' 'git "branch" -D feature' 'git -C /repo "branch" -D feature' \
  'git "checkout" -- .' 'git -C /repo "checkout" -- .' "git 'restore' ." "git -C /repo 'restore' ." \
  'git "stash" drop' 'git -C /repo "stash" clear' 'git "worktree" remove --force /tmp/wt' \
  'git -C /repo "worktree" remove --force /tmp/wt' 'git -C /repo "reflog" expire --all' 'git -C /repo "gc" --prune=now'
# Quoted prose that names a force push is still data, and the quoted safe forms pass.
passes "git commit -m 'never push --force here' && git push origin main" 'git -C /repo "push" origin main' \
  'git -C /repo "push" --force-with-lease origin main' 'git -C /repo "reset" --soft HEAD~1' \
  'git log --grep "--force" && git push origin main' 'git commit -m "reset --hard is blocked" -m "push -f too"'

# --- 5. a path checkout written as commit plus path, no `--` -----------
# `git checkout HEAD src/file.ts` overwrites the file's uncommitted edits. A
# branch checkout never takes a second positional argument, unless it makes the
# branch (-b, -B, --orphan take a start point).
blocks 'git checkout HEAD src/file.ts' 'git checkout main src/a.ts src/b.ts' 'git -C /repo checkout HEAD~1 "my file.txt"' \
  'git checkout -q HEAD src/x.ts' 'git checkout "HEAD" "src/x.ts"'
passes 'git checkout feature' 'git checkout -b new-unit origin/main' 'git checkout -B new-unit origin/main' \
  'git checkout --orphan fresh main' 'git checkout -qb new-unit origin/main' 'git checkout --track -b new-unit origin/x'
check "a commit-plus-path refusal is the checkout-of-paths one" 1 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git checkout HEAD src/file.ts')" | grep -c 'git checkout of paths')"

# --- 6. the flag is read wherever it sits in the call ------------------
# `reset` had to be followed at once by `--hard`, `switch` was never screened
# and `checkout -f` read as a branch checkout: each throws away uncommitted
# edits. git push also takes any unambiguous start of --delete and --mirror.
blocks 'git reset HEAD --hard' 'git reset -q --hard' 'git -C /repo reset origin/main --hard' \
  'git checkout -f main' 'git checkout --force main' 'git checkout -qf main' \
  'git switch -f main' 'git switch --force main' 'git switch --discard-changes' \
  'git -C /repo "switch" -f main' "git push '--force'" "git reset '--hard'" \
  'git push origin --del old' 'git push --mir origin'
passes 'git reset --soft HEAD~1' 'git reset HEAD -- src/x.ts' 'git reset -q HEAD' 'git switch main' 'git switch -c new-unit origin/main' \
  'git switch --detach abc1234' 'git reset --soft HEAD~1 && echo --hard' 'git switch main; ls -f' \
  'git commit -m "reset HEAD --hard is blocked" && git switch main' 'git push --dry-run origin main' \
  'git log --format=%s -- src/hard'

# --- 7. a force flag belongs to the push, not to the next command ------
passes 'git push origin HEAD && rg -f patterns.txt src/' 'git push origin HEAD; echo --force' \
  'git push origin HEAD | tee -f /tmp/log' 'git push origin HEAD || grep -f pats.txt --force x'
blocks 'git push origin HEAD --force && rg -f patterns.txt src/' 'git push origin main -f; ls' \
  'git fetch && git push origin main --force'

part 4
# --- 8. a quoted git word runs git, wherever it stands -------------------------
# Bash runs `"git"` exactly as `git`. Reading a quoted git word as data let the
# discard through behind an assignment or a wrapper, and each wrapper taught to
# the hook left the next one open. Every git word is read as a call instead.
blocks 'FOO=1 "git" "reset" --hard' '"git" "reset" --hard' 'env "git" clean -fdx' 'env -u git "git" reset --hard' \
  'sudo -u git "git" clean -fdx' "'git' push --force" '"/usr/bin/git" stash drop' 'cd /repo && "git" checkout -- .' \
  'nice -n 5 "git" branch -D feature'
passes '"git" status' 'FOO=1 "git" log --oneline' 'git commit -m "git"' 'env "git" clean -n' '"git" push origin main' \
  'git commit -m "git reset --hard is bad"'
# The stated limit of that rule: a git word that is data, followed by words that
# spell a discard, is refused too. The way past is to reword the command.
blocks 'git status; grep -c "git" stash drop' 'git status; echo "/usr/bin/git" restore'
# Backticks run inside double quotes, and nested ones cannot be told from data
# by their quotes. A command holding a backtick is read with no quotes at all.
blocks 'echo "`git reset --hard`"' 'echo "`echo "`printf x`"`"; git reset --hard' 'X="`git clean -fdx`"' \
  'echo "`echo "`printf x`"`"; git clean -fdx' 'echo "`echo "`printf x`"`"; git restore .'
passes 'echo "`date`"; git status' 'git commit -m "note `x` here" && git push origin main' 'echo `git rev-parse HEAD`'
# Dropping the quotes must not split a quoted argument: a path with a space
# stays one word, or the discard after it is read as a harmless subcommand.
blocks 'echo `date`; git -C "/tmp/my repo" reset --hard' 'echo `date`; git -C "/tmp/my repo" push --force origin main' \
  "echo \`date\`; git -C '/tmp/my  repo' clean -fdx"
passes 'echo `date`; git -C "/tmp/my repo" status'
# Nor may a separator inside a quoted path: the discard after it is still read.
blocks 'echo `date`; git -C "/tmp/my; repo" reset --hard' 'echo `date`; git -C "/tmp/my; repo" push --force origin main' \
  "echo \`date\`; git -C '/tmp/a|b' clean -fdx" 'echo `date`; git -C "/tmp/my; repo" restore .'
passes 'echo `date`; git -C "/tmp/my; repo" status'
# A backtick may be the option value itself, quoted or bare: no reading of the
# quotes keeps that apart, so a backtick beside a git call and a discarding
# word is refused whole.
blocks 'git -C "`realpath .`" reset --hard' 'git -C "`realpath .`" push --force origin main' 'git -C "`realpath .`" clean -fdx' \
  'git -C `realpath .` reset --hard' 'git -C "/x/`whoami`/my repo" branch -D gone' 'git -C "`pwd`" stash drop' 'git -C "`pwd`" restore .'
passes 'git -C "`realpath .`" status' 'git diff --stat `git merge-base main HEAD`' 'git push -u origin `git branch --show-current`' \
  'git -C "`pwd`" push --force-with-lease origin topic' 'git branch -d `cat /tmp/merged`'
# No word list decides: the closed reading goes through every check, so the
# shortened and less common forms are refused as they are without a backtick.
blocks 'git -C "`realpath .`" reset --hard' 'git -C "`realpath .`" push origin -d topic' 'git -C "`realpath .`" clean --force -d' \
  'git -C "`realpath .`" checkout HEAD src/file.ts'
passes 'git status; echo "reset --hard is forbidden" `date`'
# Beside a backtick, a $(...) inside a quoted string still runs and is read, one inside another too.
blocks 'echo `date`; echo "$(git reset --hard HEAD)"' 'echo `date`; X="$(git push --force origin main)"' \
  'echo `date`; echo "a $(echo "b $(git clean -fdx)")"' 'echo "`date` $(git stash drop)"' 'echo `date`; echo "$(cd /repo && git branch -D gone)"'
passes 'echo `date`; echo "$(git status)"' 'echo `date`; git commit -m "plain message"' 'echo `date`; echo "$(date): reset --hard is forbidden"'
# `<<` inside arithmetic is a shift and opens no note, so the lines after it are still read.
blocks $'echo $((1<<2))\ngit push --force origin main' $'((X = 1<<2))\ngit reset --hard HEAD' $'echo $[1<<2]\ngit clean -fdx' \
  $'X=$((Y<<=2)); echo $X\ngit stash drop' $'if ((1<<2 > 3)); then echo big; fi\ngit push -f origin main' $'echo $(( (1<<2) + 1 ))\ngit reset --hard'
# Arithmetic runs inside double quotes too, so a shift there opens no note either.
blocks $'echo "$((1<<2))"\ngit push --force origin main' $'X="a $((1<<2)) b"\ngit reset --hard HEAD' $'echo "$(echo $((1<<2)))"\ngit stash drop' \
  $'echo "$[1<<2]"\ngit clean -fdx' $'echo "$(( (1<<2) + 1 ))"\ngit push -f origin main'
passes $'echo "$((1<<2))"\ngit status' $'echo "$((1<<2))"\ncat <<EOF\ngit reset --hard\nEOF' \
  $'echo "$( (echo a) | cat <<EOF\ngit reset --hard\nEOF\n)"'
passes $'echo $((1<<2))\ngit push origin main'$'cat <<EOF\ngit push --force origin main\nEOF\ngit status' \
  $'cat <<2\ngit reset --hard\n2\ngit status' $'echo $((1<<2))\ncat <<EOF\ngit reset --hard\nEOF'
# A quoted command word is never hidden: the executable and its subcommand are read through their quotes.
blocks 'echo `date`; "git" "reset" --hard' 'echo `date`; FOO=1 "git" "reset" --hard' "echo \`date\`; 'git' 'clean' -fdx" \
  'echo `date`; "/usr/bin/git" "push" "--force" origin main'
# An escaped quote opens no string, and a backslash ends none inside single quotes.
blocks 'echo \" `date`; git reset --hard; echo \"' "echo 'a\\' \`date\`; git reset --hard; echo 'b'"
# Its stated limit: quoted prose that names a discard beside a backtick is refused.
blocks "git commit -m 'never run \`git reset --hard\` here'"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

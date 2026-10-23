#!/usr/bin/env bash
# Guard (issue 317): while a detached merge holds main (merge-unit-local.sh's state file, its pid alive), merge-lock-guard.sh
# refuses what would change main's tree under it -- git stash, checkout, reset, clean, and the other commands that move
# the index or the files -- and any edit of a file in main's checkout, naming the running merge. The orchestrator once
# stashed a live merge's half-merged files because it took the merge for killed.
#
# WHY BOTH HALVES. A guard that refuses too much stops main from reading its own repo (status, log, diff) and a Builder
# from working in its own worktree, which share the git dir with main. The ALLOWS cases are that half. A lock whose pid is
# dead is stale and blocks nothing, or a killed merge would lock main for good.
set -u
unset CLAUDE_PROJECT_DIR # the session running this test sets it; each case that needs it says so

HOOK="$(cd "$(dirname "$0")/.." && pwd)/merge-lock-guard.sh"
PASS=0 FAIL=0
R=$(cd "$(mktemp -d)" && pwd -P); trap 'kill $LIVE 2>/dev/null; rm -rf "$R"' EXIT
git -C "$R/main" init -q 2>/dev/null || { mkdir -p "$R/main"; git -C "$R/main" init -q; }
git -C "$R/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R/main/src"; echo x > "$R/main/src/a.js"; echo x > "$R/main/README.md"
git -C "$R/main" worktree add -q "$R/wt" -b builder/u
STATE=$R/main/.git/merge-unit-local.state
sleep 300 & LIVE=$!
sleep 0 & DEAD=$!; wait "$DEAD"
state() { # <pid>: a merge of u holding main
  printf 'unit=u\nsha=0123456789abcdef\ntip=0123456789abcdef\npid=%s\nstarted=1\nstage=check\nmain=%s\nlog=%s/merge-u.log\n' "$1" "$R/main" "$R" > "$STATE"; }

# run <cwd> <json>: "<rc>|<what it said>"
run() { local out rc; out=$(cd "$1" && timeout 10 bash "$HOOK" 2>&1 <<<"$2"); rc=$?; echo "$rc|$out"; } # 124: it hung
bash_in() { run "$1" "$(jq -cn --arg c "$2" '{tool_name:"Bash", tool_input:{command:$c}}')"; } # <cwd> <command>
edit_of() { run "$1" "$(jq -cn --arg f "$2" '{tool_name:"Edit", tool_input:{file_path:$f, old_string:"x", new_string:"y"}}')"; } # <cwd> <file>
check() { if [ "$2" = "${3%%|*}" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected rc $2, got $3)"; fi }
names() { if [[ $3 == *"merge of u"*"pid $LIVE"*"stage check"*"merge-u.log"* ]]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got: $3)"; fi }

state "$LIVE"
for c in "git stash" "git stash push -u" "git checkout main" "git checkout -- src/a.js" "git reset --hard" "git reset" "git clean -fd" \
         "git switch -c x" "git restore src/a.js" "git rebase main" "git add -A" "git commit -m x" \
         "cd $R/main && git stash" "git -C $R/main stash" "git --no-pager stash" "echo hi; git  checkout x" "git -c a=b reset" "git 'stash'"; do
  o=$(bash_in "$R/main" "$c"); check "a live merge refuses in main: $c" 2 "$o"
done
names "and it names the running merge, its pid, stage and log" "merge of u, pid, stage, log" "$o"
o=$(bash_in "$R/main/src" "git stash"); check "from a subdirectory of main too" 2 "$o"
o=$(bash_in "$R/wt" "git -C $R/main stash"); check "from a Builder's worktree, a command that names main's path" 2 "$o"
o=$(edit_of "$R/main" "$R/main/src/a.js"); check "an edit of a code file in main" 2 "$o"; names "and it names the merge" "merge of u" "$o"
o=$(edit_of "$R/wt" "$R/main/README.md"); check "an edit of a markdown file in main, from a Builder's worktree" 2 "$o"
o=$(edit_of "$R/main" "$R/main/src/new.js"); check "a new file in main" 2 "$o"
o=$(run "$R/main" "$(jq -cn --arg f "$R/main/src/a.js" '{tool_name:"MultiEdit", tool_input:{file_path:$f, edits:[]}}')"); check "a MultiEdit in main" 2 "$o"
# Pass 1 (r1): each git call is judged on the checkout it changes, however it is spelled and wherever it is typed.
# A clean the merge's tree check never sees deletes untracked files for good, so none of these may pass.
mkdir -p "$R/outside"
for c in "$(command -v git) clean -fd" "/usr/bin/git stash" "bash -c 'git clean -fd'" "sh -c \"git stash\"" "eval 'git stash'" \
         "git -C \"$R/main\" stash" "git stash>/dev/null" "(cd $R/wt && git add -A); git stash" "cd /nonexistent; git stash"; do
  o=$(bash_in "$R/main" "$c"); check "a live merge refuses in main: $c" 2 "$o"
done
o=$(bash_in "$R/main/src" "git -C .. stash"); check "from a subdirectory of main, git -C .." 2 "$o"
for c in "git -C ../main stash" "cd ../main && git stash" "bash -c 'cd ../main && git stash'" "git --git-dir=$R/main/.git --work-tree=$R/main stash" \
         "git -C \"\$M\" stash"; do
  o=$(bash_in "$R/wt" "$c"); check "a live merge refuses from a Builder's worktree: $c" 2 "$o"
done
o=$(bash_in "$R/outside" "git -C $R/main stash"); check "and from a folder outside the project" 2 "$o"
o=$(run "$R/outside" "$(jq -cn --arg d "$R/main" '{tool_name:"Bash", cwd:$d, tool_input:{command:"git stash"}}')"); check "the session's folder is the input's cwd" 2 "$o"
o=$(edit_of "$R/main" "README.md"); check "an edit of main's file by a relative path" 2 "$o"
# Fix round r2, the owner's ruling: a session in main runs only read-only git while a merge holds
# it, whatever folder the call names; it changes no Builder's worktree until the merge ends.
for c in "git -C $R/wt add README.md" "cd $R/wt && git stash" "git -C $R/wt -c a=b commit -m x" "git --git-dir=$R/main/.git/worktrees/wt --work-tree=$R/wt add README.md" \
         "git --work-tree=$R/wt add README.md" "git --git-dir=$R/main/.git/worktrees/wt checkout -- ."; do
  o=$(bash_in "$R/main" "$c"); check "from main, even a command on a Builder's worktree is refused: $c" 2 "$o"
done
# The class (guard-bypass, r1 and r2): no source of the target is trusted. The same clean is run once per source, each
# source taken away between runs (a cd that never runs, a variable, a git dir or work tree, an alias, a function), and
# every run is refused; from a Builder's worktree the folder may be named in any order or branch.
git -C "$R/main" config alias.cl 'clean -fd'
for c in "git clean -fd" "false && cd $R/wt; git clean -fd" "if false; then cd $R/wt; fi; git clean -fd" "git -C \"\$M\" clean -fd" \
         "GIT_DIR=$R/main/.git/worktrees/wt git clean -fd" "git cl"; do
  o=$(bash_in "$R/main" "$c"); check "class: from main: $c" 2 "$o"
done
for c in "cd ..; cd main; git clean -fd" "if false; then :; else cd ../main; fi; git clean -fd" "export GIT_DIR=$R/main/.git; git clean -fd" \
         "env GIT_WORK_TREE=$R/main git clean -fd" "f() { cd ../main; }; f; git clean -fd"; do
  o=$(bash_in "$R/wt" "$c"); check "class: from a Builder's worktree: $c" 2 "$o"
done
o=$(bash_in "$R/wt" "cd .. && cd wt && git clean -n"); check "class: a Builder's worktree may name its own folder" 0 "$o"
o=$(bash_in "$R/outside" "git stash"); check "a folder that is no checkout is not main" 0 "$o"
# Pass 2 (r2): a folder the words cannot tell, typed from outside the repo, is checked against the session's project;
# with no project either, nothing rules a merge out.
o=$(CLAUDE_PROJECT_DIR=$R/wt bash_in "$R/outside" "git -C \"\$M\" clean -fd"); check "from outside, an unreadable folder while the project has a live merge" 2 "$o"
o=$(bash_in "$R/outside" "git -C \"\$M\" clean -fd"); check "from outside, an unreadable folder with no project known" 2 "$o"
o=$(edit_of "$R/wt" "src.js"); check "a relative edit path in a Builder's worktree ends, allowed (r1: it looped until the hook's timeout)" 0 "$o"
# Pass 3 (r3), the class again: a read subcommand has writing forms (an option, a list subcommand that also deletes),
# and a word before git can move its folder. Each source of the write or the target is run alone; every run refuses.
for c in "git diff --output=README.md" "git show --output=README.md HEAD" "git fetch --update-head-ok . HEAD:main" \
         "git worktree remove --force $R/wt" "git branch -f main HEAD" "git config core.worktree $R/wt" \
         "git -c core.fsmonitor=x status" "GIT_EXTERNAL_DIFF=x git diff" "git grep -Ox stash"; do
  o=$(bash_in "$R/main" "$c"); check "class r3: from main: $c" 2 "$o"
done
for c in "env --chdir=$R/main git clean -fd" "env -C $R/main git clean -fd" "xargs -I{} git -C {} clean -fd <<< $R/main" \
         "find $R/main/src -maxdepth 0 -execdir git clean -fd \\;" "ln -s $R/main m && git -C m clean -fd" \
         "printf 'clean -fd' | xargs git -C $R/main"; do
  o=$(bash_in "$R/wt" "$c"); check "class r3: from a Builder's worktree: $c" 2 "$o"
done
o=$(bash_in "$R/wt" "if true; then GIT_EDITOR=true git stash; fi"); check "class r3: a shell keyword or assignment before git moves nothing" 0 "$o"
for c in "git branch x" "git diff 2>&1 --output=README.md"; do
  o=$(bash_in "$R/main" "$c"); check "class r3: from main, no read form: $c" 2 "$o"
done
for c in "git --no-pager log -n 3" "git status 2>&1" "git branch -a" "git worktree list" "git remote -v" "git config --get user.name" \
         "git -C $R/wt status --short"; do
  o=$(bash_in "$R/main" "$c"); check "class r3: a read form main still runs: $c" 0 "$o"
done
# Pass 4 (r4): git takes any unique prefix of a long option, so each spelling git accepts of a writing option refuses.
for c in "git grep -Orm . -- README.md" "git grep -iOrm x" "git grep --open-files-in-pager=rm x" "git grep --open-files-in-page=rm x" \
         "git grep --open-files=rm x" "git grep --op=rm x" "git grep --open-files-in-pager x" "git diff --output README.md" "git log --outp=README.md"; do
  o=$(bash_in "$R/main" "$c"); check "class r4: from main: $c" 2 "$o"
done
for c in "git grep -n -e a --or -e b" "git log --oneline -- README.md" "git diff --stat"; do
  o=$(bash_in "$R/main" "$c"); check "class r4: a read form main still runs: $c" 0 "$o"
done
# Pass 6 (r6): the shell opens a redirection's file before git starts, so `git status > .git/index` truncates main's index
# whatever git does. Any output file (any fd, any spelling, on any command of the line: a group, a loop, exec) whose
# folder is main's checkout or git dir, or cannot be read, refuses, from main or a Builder's worktree.
for c in "git status > .git/index" "git diff > README.md" "git status >.git/index" "git status >| .git/index" "git status >> README.md" \
         "git log 2> README.md" "git status &> README.md" "git status >.git/index</dev/null" "git >.git/index" "git status <> README.md" \
         "bash -c 'git status > .git/index'" "{ git status; } > .git/index" "(git status) > .git/index" "exec > README.md; git status" \
         "for i in 1; do git status; done > .git/index" "git diff > \"\$OUT\""; do
  o=$(bash_in "$R/main" "$c"); check "class r6: from main: $c" 2 "$o"
done
for c in "git status > $R/main/.git/index" "git diff > ../main/README.md" "cd ../main && git status > .git/index" "git diff > \"\$M\"/x" \
         "{ git status; } > ../main/README.md"; do
  o=$(bash_in "$R/wt" "$c"); check "class r6: from a Builder's worktree: $c" 2 "$o"
done
for c in "git status > /dev/null" "git rev-parse HEAD 2>/dev/null" "git branch --show-current 2>/dev/null" "git log < README.md" \
         "git diff > $R/outside/p.patch" "git log --format='%h>%s'"; do
  o=$(bash_in "$R/main" "$c"); check "class r6: a read form main still runs: $c" 0 "$o"
done
for c in "git diff > $R/outside/p.patch" "git diff > p.patch"; do
  o=$(bash_in "$R/wt" "$c"); check "class r6: a Builder's worktree may write a read's output outside main: $c" 0 "$o"
done
# The owner's ruling on r6 (the class, fifth pass): a read is only one way to write. In main's checkout every command
# is an allow list, git or not, so a read piped into a writer and a writer with no git at all both refuse; and from
# any checkout, a git call that moves main's branch or sets what main's git runs refuses (git itself allows these).
for c in "git status | tee .git/index" "git status | tee -a README.md" "git log | dd of=.git/index" "git status | cp /dev/stdin README.md" \
         "git log -p | patch -p1" "git show HEAD:README.md | sh" "rm README.md" "sed -i '' s/x/y/ README.md" "sed -i.bak s/x/y/ README.md" \
         "sed s/x/y/w README.md" "sed -n /x/wREADME.md README.md" "sed s/x/y/e README.md" "sed -f s.sed README.md" "git status | xargs rm" \
         "./ls" "X=1 cat README.md" "rg --pre=rm x" "node -e 1" "bash" "cat README.md | bash -s" "env -C . git status"; do
  o=$(bash_in "$R/main" "$c"); check "class r6 ruling: from main: $c" 2 "$o"
done
o=$(bash_in "$R/main" "rm README.md"); names "and it names the merge" "merge of u" "$o"
for c in "git update-ref refs/heads/main HEAD" "git config core.fsmonitor x" "git config --worktree core.pager x" "git gc --prune=now" \
         "git prune" "git repack -ad" "git reflog expire --all" "git branch -M main x" "git branch --mov main x" "git branch -vm main x" \
         "git fetch -u . builder/u:main" "git fetch --update-h . builder/u:main" "git checkout --ignore-other-worktrees -B main" \
         "git switch --ignore-o -C main" "git symbolic-ref refs/heads/main refs/heads/builder/u" "git worktree prune" "git -C $R/outside update-ref x HEAD"; do
  o=$(bash_in "$R/wt" "$c"); check "class r6 ruling: from a Builder's worktree: $c" 2 "$o"
done
for c in "ls -la" "cat README.md | grep x | head -1" "rg -n x ." "jq -n 1" "sed -n 1,20p README.md" "sed -n s/^x//p README.md" "sed -E -e /x/d README.md" \
         "echo hi; printf %s x" "cd src && ls" "x=1" "if test -f README.md; then echo y; fi" "orca-ide orchestration check --json" \
         "sleep 0; date; pwd" "kill -0 $LIVE" "git log --oneline | head -3" "[[ -f README.md ]] && wc -l README.md"; do
  o=$(bash_in "$R/main" "$c"); check "class r6 ruling: main still runs: $c" 0 "$o"
done
for c in "git commit --allow-empty -m x" "git branch -v" "git config --get user.name" "git fetch origin" "git symbolic-ref --short HEAD" \
         "git reflog -n 3" "rm src.js" "git push -u origin builder/u"; do
  o=$(bash_in "$R/wt" "$c"); check "class r6 ruling: a Builder's worktree still runs: $c" 0 "$o"
done
# Pass 7 (r7), the class again: a target's folder is not the file the shell writes. The same write into main's file is
# run once per source of its place (an expansion, a glob, a link, a dangling link, a hard link, a link the line makes,
# an Edit of a link), each source alone; every run refuses. And a listed program takes only options that read.
ln -s "$R/main/README.md" "$R/wt/linked.md"; ln -s "$R/main/new.md" "$R/wt/dangling.md"; ln "$R/main/README.md" "$R/wt/hard.md"
for c in "git diff > \"\$OUT\"" "git diff > \$OUT" "git diff > READ*" "git diff > linked.md" "git diff > $R/wt/linked.md" "git diff > dangling.md" \
         "git diff > hard.md" "ln -s $R/main/README.md l2 && git diff > l2"; do
  o=$(bash_in "$R/wt" "$c"); check "class r7: from a Builder's worktree: $c" 2 "$o"
done
for f in linked.md dangling.md hard.md; do
  o=$(edit_of "$R/wt" "$R/wt/$f"); check "class r7: from a Builder's worktree, an edit of $f" 2 "$o"
done
for c in "rg -H --color=always --hostname-bin=./w --hyperlink-format='file://{host}{path}' x README.md" "rg --pre-glob=x --pre=rm x" "rg -z x"; do
  o=$(bash_in "$R/main" "$c"); check "class r7: from main: $c" 2 "$o"
done
for c in "git diff > src.patch" "git diff >> README.md" "git diff > $R/outside/p.patch"; do
  o=$(bash_in "$R/wt" "$c"); check "class r7: a Builder's worktree still writes its own or a new file: $c" 0 "$o"
done
o=$(edit_of "$R/wt" "$R/wt/README.md"); check "class r7: a Builder's worktree still edits its own file" 0 "$o"
o=$(bash_in "$R/main" "rg -in -g *.md -C2 --hidden x ."); check "class r7: main still runs rg with options that read" 0 "$o"
# Pass 8 (r8), the class again: a quote does not keep a string inert. bash evaluates a name's subscript (test -v, wait -p),
# arithmetic, ${!x} and ${x@P}, and runs any $( ) the string holds. The same rm is run once per evaluator and per source
# of the string (a quoted literal, a stored variable, an ANSI-C quote, printf -v with no $ typed), each alone.
for c in "test -v 'a[\$(rm README.md)]'" "[ -v 'a[\$(rm README.md)]' ]" "[[ -v 'a[\$(rm README.md)]' ]]" "sleep 1 & wait -n -p 'a[\$(rm README.md)]'" \
         "x='a[\$(rm README.md)]'; echo \$[x]" "x='a[\$(rm README.md)]'; echo \${a[x]}" "x='a[\$(rm README.md)]'; echo \${!x}" \
         "x='a[\$(rm README.md)]'; echo \"\${x@P}\"" "x=\$'a[\\x24(rm README.md)]'; test -v \"\$x\"" "printf -v x 'z[\\x24(rm README.md)]'; test -v 'a[x]'"; do
  o=$(bash_in "$R/main" "$c"); check "class r8: from main: $c" 2 "$o"
done
# The owner's ruling on r8: no $ and no backtick anywhere in main's command, and printf takes no -v. That closes the
# r7 gaps too (a backtick in double quotes, printf -v and [[ ]] on a quoted or stored subscript) and any plain $.
for c in "echo \"\`rm README.md\`\"" "printf -v 'a[\$(rm README.md)]' %s 1" "[[ 'a[\$(rm README.md)]' -eq 0 ]]" \
         "printf -v x 'z[\\x24(rm README.md)]'; [[ x -eq 0 ]]" "printf -v x 'z[\\x24(rm README.md)]'" "printf -vx 1" "echo \$HOME"; do
  o=$(bash_in "$R/main" "$c"); check "class r8 ruling: from main: $c" 2 "$o"
done
o=$(bash_in "$R/main" "echo \$HOME"); names "and it names the merge" "merge of u" "$o"
for c in "printf '%s\n' x" "test -f README.md" "[ -n x ]" "[[ -f README.md ]]" "grep -n 'x' README.md"; do
  o=$(bash_in "$R/main" "$c"); check "class r8 ruling: main still runs: $c" 0 "$o"
done
o=$(bash_in "$R/wt" "git log --oneline -n 1 -- \"\$F\""); check "class r8 ruling: a Builder's worktree still types \$" 0 "$o"
# Pass 14 (r14), the class again: git writes files the words name in no folder slot -- a variable git reads as a path
# (its index, its config, a trace file), or an argument (an option's value, a glued short option's, a plain word). Even
# a read form writes the index and the trace. The same write into main is run once per source, each alone; then the
# merge's pid is swapped for a dead one and the same commands pass, so only a live merge refuses them.
R14=("GIT_INDEX_FILE=$R/main/.git/index git read-tree HEAD" "GIT_INDEX_FILE=$R/main/.git/index git add README.md"
     "GIT_INDEX_FILE=../main/.git/index git status" "GIT_TRACE=$R/main/README.md git status" "GIT_TRACE2_EVENT=$R/main/README.md git log -1"
     "git diff --output=$R/main/README.md" "git read-tree --index-output=$R/main/.git/index HEAD" "git archive -o$R/main/x.tar HEAD"
     "git format-patch -o $R/main/p HEAD" "git bundle create ../main/b.bundle HEAD" "git checkout-index -a --prefix=$R/main/"
     "git worktree add $R/main/sub" "true; git worktree add $R/main/sub" "git diff --output=hard.md")
R14OUT=("GIT_CONFIG_GLOBAL=$R/main/src/a.js git config --global a.b c" "GIT_CONFIG_SYSTEM=$R/main/.git/config git config --system a.b c"
        "GIT_CONFIG=$R/main/.git/config git config a.b c" "GIT_COMMON_DIR=$R/main/.git git update-ref refs/heads/main HEAD"
        "GIT_OBJECT_DIRECTORY=$R/main/.git/objects git prune")
for c in "${R14[@]}"; do o=$(bash_in "$R/wt" "$c"); check "class r14: from a Builder's worktree: $c" 2 "$o"; done
for c in "${R14OUT[@]}"; do o=$(bash_in "$R/outside" "$c"); check "class r14: from a folder outside the project: $c" 2 "$o"; done
state "$DEAD"
for c in "${R14[@]}"; do o=$(bash_in "$R/wt" "$c"); check "class r14: no live merge, a Builder's worktree runs: $c" 0 "$o"; done
for c in "${R14OUT[@]}"; do o=$(bash_in "$R/outside" "$c"); check "class r14: no live merge, outside runs: $c" 0 "$o"; done
state "$LIVE"
for c in "GIT_INDEX_FILE=$R/outside/idx git read-tree HEAD" "GIT_TRACE=1 git status" "GIT_TRACE=$R/outside/t git status" \
         "git diff --output=$R/outside/p.patch" "git commit -am x" "git checkout -b feature/x && git log -1" "git worktree add ../w2"; do
  o=$(bash_in "$R/wt" "$c"); check "class r14: a Builder's worktree still runs: $c" 0 "$o"
done
# Pass 15 (r15): a path that is a folder already is where git writes (format-patch -o, a GIT_TRACE2 folder), not its
# parent. The same write into main's checkout once per source of the folder, each alone.
ln -s "$R/main" "$R/wt/maindir"
R15=("git format-patch --numbered-files -1 -o $R/main HEAD" "git format-patch -1 --output-directory=$R/main HEAD"
     "git format-patch -1 -o ../main HEAD" "git format-patch -1 -o maindir HEAD" "git format-patch -1 -o $R/main/ HEAD"
     "GIT_TRACE2_EVENT=$R/main git log -1" "GIT_TRACE2_EVENT=maindir git status")
for c in "${R15[@]}"; do o=$(bash_in "$R/wt" "$c"); check "class r15: from a Builder's worktree: $c" 2 "$o"; done
state "$DEAD"
for c in "${R15[@]}"; do o=$(bash_in "$R/wt" "$c"); check "class r15: no live merge, a Builder's worktree runs: $c" 0 "$o"; done
state "$LIVE"
for c in "git format-patch -1 -o $R/outside HEAD" "git format-patch -1 -o . HEAD" "GIT_TRACE2_EVENT=$R/outside git status"; do
  o=$(bash_in "$R/wt" "$c"); check "class r15: a Builder's worktree still runs: $c" 0 "$o"
done

for c in "git status" "git log --oneline" "git diff HEAD" "git show HEAD" "git branch" "git log --grep='git stash'" \
         "grep -rn 'git checkout' docs" "git merge-base main HEAD" "bash scripts/merge-unit-local.sh u" "ls"; do
  o=$(bash_in "$R/main" "$c"); check "a live merge still allows in main: $c" 0 "$o"
done
o=$(bash_in "$R/wt" "git stash"); check "a Builder's worktree may stash its own work" 0 "$o"
o=$(bash_in "$R/wt" "git checkout -b y"); check "and check out in its own worktree" 0 "$o"
o=$(edit_of "$R/wt" "$R/wt/src.js"); check "and edit its own files" 0 "$o"
o=$(edit_of "$R/main" "$R/outside.txt"); check "a file outside main's checkout" 0 "$o"

state "$DEAD"
o=$(bash_in "$R/main" "git stash"); check "a stale lock (its pid dead) does not block git stash" 0 "$o"
o=$(edit_of "$R/main" "$R/main/src/a.js"); check "or an edit" 0 "$o"
o=$(CLAUDE_PROJECT_DIR=$R/wt bash_in "$R/outside" "git -C \"\$M\" clean -fd"); check "or an unreadable folder from outside, the project known" 0 "$o"
rm -f "$STATE"
o=$(bash_in "$R/main" "git stash"); check "no merge, no refusal" 0 "$o"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

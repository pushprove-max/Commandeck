#!/usr/bin/env bash
# covers: hooks/bash-guardrails.sh
# Issue 665: Commandeck tests never run on the Mac. A direct `bash <dir>/__tests__/<name>.test.sh` there skips
# run-shell-tests.sh's hand-off to the PC and loads the Mac, so the hook refuses it, naming run-shell-tests.sh;
# the hand-off itself and a run on the PC (any other host) go through. Its own file: bash-guardrails.test.sh runs
# near the 500-line cap.
set -u
export COMMANDECK_REVIEWER=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# A checkout shaped like Commandeck's: the runner, and one test file it would hand off.
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
mkdir -p "$R/scripts/__tests__"; : >"$R/scripts/run-shell-tests.sh"; : >"$R/scripts/__tests__/x.test.sh"
mkdir -p "$R/.claude-plugin"; printf '{\n  "name": "commandeck"\n}\n' >"$R/.claude-plugin/plugin.json"
# hook <host> <command> -- prints the exit code, then the refusal text on one line.
hook() {
  local E; E=$(cd "$R" && jq -cn --arg c "$2" --arg d "$R" '{tool_input:{command:$c},cwd:$d}' \
    | COMMANDECK_HOST_OS=$1 "$HOOK" 2>&1 >/dev/null); echo "$? $(tr '\n' ' ' <<<"$E")"
}
MAC=$(hook Darwin 'bash scripts/__tests__/x.test.sh')
VIA=$(hook Darwin 'bash scripts/run-shell-tests.sh scripts/__tests__/x.test.sh')
PC=$(hook Linux 'bash scripts/__tests__/x.test.sh')
check "a direct test run on the Mac is refused naming run-shell-tests.sh; the hand-off and the PC run pass" \
  "2 1 0 0" "${MAC%% *} $(grep -c 'run-shell-tests.sh' <<<"$MAC") ${VIA%% *} ${PC%% *}"
# Main's widening (2026-11-05): a run inside a wrapper, or after a `cd` that makes the path short, ran on the Mac. Only
# the runner (wrapped or not) and a command that reads the file without running it pass.
GOT=
for c in 'timeout 60 bash scripts/__tests__/x.test.sh' 'env X=1 nohup bash scripts/__tests__/x.test.sh' \
  'cd scripts/__tests__ && bash x.test.sh' 'cd scripts && ./__tests__/x.test.sh' 'bash -c "bash scripts/__tests__/x.test.sh"' \
  'timeout 600 bash scripts/run-shell-tests.sh scripts/__tests__/x.test.sh' 'cd scripts/__tests__ && grep -n check x.test.sh'; do
  O=$(hook Darwin "$c"); GOT+="${O%% *}"
done
check "a wrapped run or one after cd is refused too; the wrapped hand-off and a reader pass" "2222200" "$GOT"
# Issue 666: a test file typed after sh or zsh runs on the Mac just as under bash (BASH_ENV, which bash alone reads,
# never sees it), so the hook refuses it with the same message naming the PC route; the runner still hands off.
# Stated limit (main's ruling msg_816ad8d781da): a test a script starts through sh or zsh is not caught.
GOT=
for c in 'sh scripts/__tests__/x.test.sh' 'zsh scripts/__tests__/x.test.sh' '/bin/zsh scripts/__tests__/x.test.sh' 'timeout 60 sh scripts/__tests__/x.test.sh'; do
  O=$(hook Darwin "$c"); GOT+="${O%% *}$(grep -c 'run-shell-tests.sh' <<<"$O") "
done
check "sh_and_zsh_test_file_on_mac_refused (#666): typed sh and zsh runs are refused naming run-shell-tests.sh" "21 21 21 21 " "$GOT"
# The runner needs Bash 4 (requirements.sh), so its route is bash or sh; zsh cannot run it.
check "run_shell_tests_on_mac_still_offloads (#665, #666): the runner, under bash or sh, passes on the Mac" "0 0" \
  "$(for c in 'bash scripts/run-shell-tests.sh scripts/__tests__/x.test.sh' 'sh scripts/run-shell-tests.sh scripts/__tests__/x.test.sh'; do O=$(hook Darwin "$c"); printf '%s ' "${O%% *}"; done | sed 's/ $//')"
# Issue 668: a host project with its own scripts/run-shell-tests.sh but no Commandeck marker is no checkout: its test runs.
H=$(mktemp -d); mkdir -p "$H/scripts/__tests__"; : >"$H/scripts/run-shell-tests.sh"; : >"$H/scripts/__tests__/h.test.sh"
O=$(jq -cn --arg c "bash $H/scripts/__tests__/h.test.sh" --arg d "$H" '{tool_input:{command:$c},cwd:$d}' | COMMANDECK_HOST_OS=Darwin "$HOOK" 2>/dev/null >/dev/null; echo $?)
rm -rf "$H"
check "host_project_runner_is_not_a_commandeck_checkout (#668): a host project's test with its own runner is not refused" 0 "$O"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

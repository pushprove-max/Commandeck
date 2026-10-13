#!/usr/bin/env bash
# timeout: 600 -- 294s beside one other slow file on the Mac (2026-10-13), over 300s beside four; some 25 set-up and uninstall rounds, three of them waiting 5 s on a held lock
# uninstall-snapshot.test.sh -- the owner asked for an uninstall that leaves
# the machine exactly as it was. What this pins: snapshot, set up, do a unit's
# worth of work, uninstall, snapshot again, and the two match byte for byte --
# with the data deleted, nothing differs; with the data kept, only the data
# differs. For both scopes, with another tool's entries in every file the
# plugin merges into, with two projects sharing the machine's parts, and
# after a setup that failed half way.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"

# work <project dir> -- what one unit leaves behind: a worktree set up and removed, a
# question in the ledger, a hook fire, a ruling, a scratch file and one dashboard collect.
work() {
  local name=${1##*/} wt
  wt=$HOME/orca/workspaces/$name/u1
  git -C "$1" worktree add -q "$wt" -b u1 && run "$wt" worktree-setup.sh "$wt" >/dev/null 2>&1
  mkdir -p "$1/.claude/metrics"; : > "$1/.claude/metrics/decisions.jsonl"
  run "$1" decision.sh add d1 "Ship it?" "wait" u1 >/dev/null 2>&1
  ( cd "$1" && echo '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}' \
      | env -u COMMANDECK_HOOK_FIRE_LOG PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$1" bash "$PLUGIN/hooks/git-safety.sh" >/dev/null 2>&1 )
  mkdir -p "$HOME/.claude/rulings" "$HOME/.commandeck/scratch/$(printf %s "$1" | tr -c 'A-Za-z0-9' '-')"
  echo '{}' >> "$HOME/.claude/rulings/$name.jsonl"
  echo note > "$HOME/.commandeck/scratch/$(printf %s "$1" | tr -c 'A-Za-z0-9' '-')/seat-x.txt"
  run "$1" dashboard.sh >/dev/null 2>&1
  git -C "$1" worktree remove --force "$wt" && git -C "$1" branch -q -D u1
}
# Where the plugin's own data lives: the only paths a keep-data uninstall may leave.
DATA='^[0-9a-f]* (home/\.commandeck/|home/\.claude/hook-fire-log/|home/\.claude/rulings/|home/orca/|proj[^/]*/\.claude/metrics/)|^(home/\.commandeck/|home/\.claude/hook-fire-log/|home/\.claude/rulings/|home/orca/|proj[^/]*/\.claude/metrics/)'
changed() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep '^[<>]' | sed 's/^[<>] //' | sort -u; }

BEFORE=$(snap)
for scope in project machine; do
  run "$PROJ" setup.sh "${ANSWERS[@]}" --scope "$scope" >"$T/setup.out" 2>&1; check "$scope scope: setup succeeds" 0 $?
  check "$scope scope: setup changed the machine" 1 "$([ "$(snap)" != "$BEFORE" ] && echo 1 || echo 0)"
  work "$PROJ"
  run "$PROJ" uninstall.sh >"$T/uninstall.out" 2>&1; check "$scope scope: uninstall succeeds" 0 $?
  AFTER=$(snap)
  check "$scope scope: with the data kept, only the plugin's data differs" '' "$(changed "$BEFORE" "$AFTER" | grep -vE "$DATA")"
  check "$scope scope: the data is kept" 1 "$(grep -c 'proj/.claude/metrics/decisions.jsonl$' <<<"$AFTER")"
  check "$scope scope: no job is left running" 0 "$(ls "$HOME/.config/systemd/user" 2>/dev/null | grep -c commandeck)"
  run "$PROJ" uninstall.sh --delete-data >>"$T/uninstall.out" 2>&1; check "$scope scope: deleting the data afterwards succeeds" 0 $?
  check "$scope scope: with the data deleted, the machine is as it was" '' "$(changed "$BEFORE" "$(snap)")"
done

# --- one step: uninstall --delete-data straight after the work ---
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; work "$PROJ"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "set up, worked, uninstalled with the data: the machine is as it was" '' "$(changed "$BEFORE" "$(snap)")"
# The metrics folder may hold the owner's or another tool's files: only the
# plugin's own ledgers go with the data.
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; work "$PROJ"; echo theirs > "$PROJ/.claude/metrics/own.csv"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "deleting the data leaves a file in the metrics folder that is not the plugin's" 'theirs|own.csv' \
  "$(cat "$PROJ/.claude/metrics/own.csv" 2>/dev/null)|$(ls "$PROJ/.claude/metrics" 2>/dev/null | paste -sd' ' -)"
rm -rf "$PROJ/.claude/metrics"; rmdir "$PROJ/.claude" 2>/dev/null || true

# --- the Claude-only profile never touches Codex ---
run "$PROJ" setup.sh --profile claude --name Ada >/dev/null 2>&1
check "the Claude-only profile leaves Codex's files alone" '' "$(changed "$BEFORE" "$(snap)" | grep 'home/\.codex/')"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "and uninstalls to the machine as it was" '' "$(changed "$BEFORE" "$(snap)")"

# --- two projects share the machine's parts: the first uninstall leaves them for the second ---
project "$T/proj2"; BEFORE2=$(snap)
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$T/proj2" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "the first project is as it was" '' "$(changed "$BEFORE2" "$(snap)" | grep ' proj/\|^proj/')"
check "the second project still has Codex's hooks" 5 "$(jq '[.hooks[][].hooks[] | select(.command | contains("/hooks/codex-dispatch.sh"))] | length' "$HOME/.codex/hooks.json")"
check "and the dashboard job" 1 "$(ls "$HOME/.config/systemd/user" 2>/dev/null | grep -c 'commandeck-dashboard')"
run "$T/proj2" uninstall.sh --delete-data >/dev/null 2>&1
check "the last uninstall takes the machine's parts too" '' "$(changed "$BEFORE2" "$(snap)")"
rm -rf "$T/proj2"

# --- the owner edited a merged file after setup: the edit survives, and uninstall says so ---
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
jq '.permissions.allow += ["Bash(owner-added:*)"]' "$PROJ/.claude/settings.json" > "$T/s.json" && cp "$T/s.json" "$PROJ/.claude/settings.json"
run "$PROJ" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1
check "an edit made after setup is kept" '["Bash(make:*)","Bash(owner-added:*)"]' "$(jq -c '.permissions.allow' "$PROJ/.claude/settings.json")"
check "and uninstall names the file it could not put back exactly" 1 "$(grep -c 'changed since setup.*proj/.claude/settings.json' "$T/uninstall.out")"
git -C "$PROJ" checkout -q -- . 2>/dev/null; printf '{"permissions": {"allow": ["Bash(make:*)"]}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "./own-stop.sh"}]}]}}\n' > "$PROJ/.claude/settings.json"
check "(the fixture is back to its start)" '' "$(changed "$BEFORE" "$(snap)")"

# --- a rule the owner already had is the owner's: setup adds it nowhere, and uninstall leaves it ---
jq '.permissions.allow += ["Bash(orca-ide terminal:*)"]' "$PROJ/.claude/settings.json" > "$T/s.json" && cp "$T/s.json" "$PROJ/.claude/settings.json"; BEFORE4=$(snap)
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
check "setup does not add a rule that is already there" 1 "$(jq '[.permissions.allow[] | select(. == "Bash(orca-ide terminal:*)")] | length' "$PROJ/.claude/settings.json")"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "after two setups and an uninstall the owner's own rule is still there" '' "$(changed "$BEFORE4" "$(snap)")"
printf '{"permissions": {"allow": ["Bash(make:*)"]}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "./own-stop.sh"}]}]}}\n' > "$PROJ/.claude/settings.json"

# --- a project someone registered with the dashboard by hand is not the plugin's to forget ---
mkdir -p "$HOME/.commandeck/dashboard"; echo "$T/by-hand" > "$HOME/.commandeck/dashboard/projects"; BEFORE3=$(snap)
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; work "$PROJ"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "its line in the registry outlives the last uninstall, and nothing else is left" '' "$(changed "$BEFORE3" "$(snap)")"
rm -rf "$HOME/.commandeck"
# The same for this project's own line when the owner put it there before setup ran.
mkdir -p "$HOME/.commandeck/dashboard"; echo "$PROJ" > "$HOME/.commandeck/dashboard/projects"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "a registration that predates setup outlives uninstall" 1 "$(grep -cxF -- "$PROJ" "$HOME/.commandeck/dashboard/projects" 2>/dev/null)"
rm -rf "$HOME/.commandeck"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
check "setup registers a project that was not there" 1 "$(grep -cxF -- "$PROJ" "$HOME/.commandeck/dashboard/projects" 2>/dev/null)"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh >/dev/null 2>&1
check "and uninstall takes its own registration back out, after a second setup too" 0 "$(grep -cxF -- "$PROJ" "$HOME/.commandeck/dashboard/projects" 2>/dev/null)"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1; rm -rf "$HOME/.commandeck"

# --- a status line and extra dashboard names: the earlier ones come back ---
SL=$HOME/.claude/settings.json
run "$PROJ" setup.sh "${ANSWERS[@]}" --hosts box.tailnet.example --status-line 'bash ~/line.sh' >"$T/setup.out" 2>&1; check "setup with a status line and a dashboard name succeeds" 0 $?
check "the status line is the one given" '{"type":"command","command":"bash ~/line.sh"}' "$(jq -c .statusLine "$SL")"
check "the install record holds the one the owner had" '~/.claude/status-lines/other.sh' "$(jq -r '.statusLine.was.command' "$HOME/.commandeck/install/_machine.json")"
check "setup says the earlier one comes back at uninstall" 1 "$(grep -c '^Status line: set to .*line.sh.*uninstall' "$T/setup.out")"
run "$PROJ" setup.sh --status-line 'bash ~/second.sh' >/dev/null 2>&1
check "a second answer does not take the first for the owner's own" '~/.claude/status-lines/other.sh' "$(jq -r '.statusLine.was.command' "$HOME/.commandeck/install/_machine.json")"
run "$PROJ" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1
check "uninstall puts the earlier status line and the closed name list back: the machine is as it was" '' "$(changed "$BEFORE" "$(snap)")"
# No status line before: none after. One the owner changed after setup stays.
jq 'del(.statusLine)' "$SL" > "$T/s.json" && cp "$T/s.json" "$SL"; BEFORE5=$(snap)
run "$PROJ" setup.sh "${ANSWERS[@]}" --status-line 'bash ~/line.sh' >/dev/null 2>&1; run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "with none before, uninstall leaves none" '' "$(changed "$BEFORE5" "$(snap)")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --status-line 'bash ~/line.sh' >/dev/null 2>&1
jq '.statusLine.command = "bash ~/later.sh"' "$SL" > "$T/s.json" && cp "$T/s.json" "$SL"
run "$PROJ" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1
check "a status line the owner set after setup is kept" 'bash ~/later.sh' "$(jq -r '.statusLine.command' "$SL")"
check "and uninstall says so" 1 "$(grep -c 'status line.*changed since setup' "$T/uninstall.out")"
printf '{\n  "statusLine": {"type": "command", "command": "~/.claude/status-lines/other.sh"},\n  "permissions": {"allow": ["Bash(ls:*)"]},\n  "enabledPlugins": {"other@market": true}\n}\n' > "$SL"
check "(the fixture is back to its start)" '' "$(changed "$BEFORE" "$(snap)")"

# --- the owner's own ponytail skill, or the whole add-on, is the owner's ---
mkdir -p "$HOME/.claude/skills/ponytail"; echo mine > "$HOME/.claude/skills/ponytail/SKILL.md"; BEFORE6=$(snap)
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/setup.out" 2>&1
check "a ponytail skill the owner already has is left as written" 'mine' "$(cat "$HOME/.claude/skills/ponytail/SKILL.md")"
check "and setup says so" 1 "$(grep -c 'ponytail.*already.*left as it is' "$T/setup.out")"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "and it outlives uninstall" '' "$(changed "$BEFORE6" "$(snap)")"
rm -rf "$HOME/.claude/skills"
jq '.enabledPlugins["ponytail@ponytail"] = true' "$SL" > "$T/s.json" && cp "$T/s.json" "$SL"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
check "with the whole ponytail add-on installed, setup adds no second copy" 0 "$(ls "$HOME/.claude" | grep -c '^skills$')"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
printf '{\n  "statusLine": {"type": "command", "command": "~/.claude/status-lines/other.sh"},\n  "permissions": {"allow": ["Bash(ls:*)"]},\n  "enabledPlugins": {"other@market": true}\n}\n' > "$SL"
check "(the fixture is back to its start)" '' "$(changed "$BEFORE" "$(snap)")"

# --- a setup that fails half way: the manifest already names what it touched, and uninstall puts it back ---
chmod a-w "$HOME/.codex"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/setup.out" 2>&1; check "a setup that cannot write Codex's hooks fails" 1 $?
chmod u+w "$HOME/.codex"
check "the manifest was written before the first change" 1 "$([ -s "$(mf "$PROJ")" ] && echo 1 || echo 0)"
check "and it names the project's config, which setup had already written" 1 \
  "$(jq --arg p "$PROJ/.claude/commandeck.json" '[.entries | has($p)] | map(select(.)) | length' "$(mf "$PROJ")" 2>/dev/null)"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "uninstall after the failed setup: the machine is as it was" '' "$(changed "$BEFORE" "$(snap)")"

# --- the finished-builds record is the plugin's data: kept unless --delete-data, and then only this project's goes ---
# The dashboard lists a project's merged builds from ~/.commandeck/builds/<project>.jsonl. Left behind, a project
# set up again later would list builds of a checkout the owner asked to forget.
B=$HOME/.commandeck/builds
# The file is named by the folder's name alone, so every checkout of that name writes it: a line says whose it is.
mine() { printf '{"main":"%s","unit":"%s"}\n' "$(cd "${2:-$PROJ}" && pwd -P)" "$1"; }
TWIN='{"main":"/elsewhere/proj","unit":"twin"}'
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
mkdir -p "$B"; { mine a; echo "$TWIN"; echo '{"unit":"no checkout named"}'; echo '{"main":"torn'; mine b; } > "$B/proj.jsonl"
echo '{"unit":"theirs"}' > "$B/other.jsonl"; echo x > "$B/proj.jsonl.mine"
run "$PROJ" uninstall.sh >/dev/null 2>&1
check "without --delete-data the finished-builds record stays whole" 5 "$(wc -l < "$B/proj.jsonl" | tr -d ' ')"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "with it this checkout's lines go, and another checkout's of the same folder name, a line naming none and a torn one stay" \
  "$TWIN|{\"unit\":\"no checkout named\"}|{\"main\":\"torn" "$(paste -sd'|' "$B/proj.jsonl")"
check "another project's record and a file beside it are not touched" "other.jsonl proj.jsonl proj.jsonl.mine" "$(ls "$B" | paste -sd' ' -)"
rm -rf "$B"; mkdir -p "$B"; mine only > "$B/proj.jsonl"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "a record holding only this checkout's lines goes whole, and the empty builds folder with it" no "$([ -e "$B" ] && echo yes || echo no)"
# A link is not a file the plugin made: neither it nor what it points at is touched.
mkdir -p "$B" "$T/outside"; mine elsewhere > "$T/outside/proj.jsonl"; ln -s "$T/outside/proj.jsonl" "$B/proj.jsonl"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "a record that is a link out of the data folder: the file it points at is left as it was" "$(mine elsewhere)" "$(cat "$T/outside/proj.jsonl" 2>/dev/null)"
rm -rf "$B"; ln -s "$T/outside" "$B"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "a builds folder that is a link out of the data folder: nothing in it is changed" "$(mine elsewhere)" "$(cat "$T/outside/proj.jsonl" 2>/dev/null)"
rm -rf "$B" "$T/outside"
# Two checkouts of one folder name, both uninstalled with the data kept: no set-up record names either any more,
# and deleting one's data must still leave the other's builds.
mkdir -p "$T/twin"; project "$T/twin/proj"
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$T/twin/proj" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
mkdir -p "$B"; { mine a; mine b "$T/twin/proj"; } > "$B/proj.jsonl"
run "$PROJ" uninstall.sh >/dev/null 2>&1; run "$T/twin/proj" uninstall.sh >/dev/null 2>&1
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "both uninstalled with the data kept, then one deleted: the other checkout's builds are still there" "$(mine b "$T/twin/proj")" "$(cat "$B/proj.jsonl" 2>/dev/null)"
run "$T/twin/proj" uninstall.sh --delete-data >/dev/null 2>&1
check "and its own delete takes them" no "$([ -e "$B" ] && echo yes || echo no)"
rm -rf "$T/twin"
# A same-named checkout's merge appends to this file. Both take one lock, on the home folder (it is never removed,
# so both always lock the same thing), and a line appended while uninstall rewrites the file is never lost: while
# another holds the lock, uninstall changes nothing and says so.
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
mkdir -p "$B"; mine a > "$B/proj.jsonl"
flock "$HOME" bash -c "touch '$T/held'; while [ ! -e '$T/release' ]; do sleep 0.2; done" & HOLDER=$!
while [ ! -e "$T/held" ]; do sleep 0.1; done
run "$PROJ" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1
check "the record's lock held by another: uninstall leaves the record as it was" "$(mine a)" "$(cat "$B/proj.jsonl" 2>/dev/null)"
check "and says so" 1 "$(grep -c 'finished-builds record is left as it was' "$T/uninstall.out")"
touch "$T/release"; wait "$HOLDER"; rm -f "$T/held" "$T/release"
run "$PROJ" uninstall.sh --delete-data >/dev/null 2>&1
check "run again with the lock free, the record goes" no "$([ -e "$B" ] && echo yes || echo no)"
# The lock is not on the builds folder, which an uninstall removes: an uninstall waiting for the lock while the folder
# is removed and made again, and a same-named checkout's merge appends, must still see that line and keep it.
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1
mkdir -p "$B"; mine a > "$B/proj.jsonl"
flock "$HOME" bash -c "touch '$T/held'; while [ ! -e '$T/release' ]; do sleep 0.2; done" & HOLDER=$!
while [ ! -e "$T/held" ]; do sleep 0.1; done
run "$PROJ" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1 & UN=$!
# waiting <pid>: some process under it is the uninstall's own wait for the lock.
under() { local c; for c in $(pgrep -P "$1"); do echo "$c"; under "$c"; done; }
waiting() { local c; for c in $(under "$1"); do case "$(ps -o args= -p "$c" 2>/dev/null)" in *"flock -w 5 8"*) return 0 ;; esac; done; return 1; }
n=0; until waiting "$UN" || [ $((n += 1)) -gt 400 ]; do sleep 0.1; done
check "the uninstall waits for the lock another holds" yes "$(waiting "$UN" && echo yes || echo no)"
rm -rf "$B"; mkdir -p "$B"; { mine a; echo "$TWIN"; } > "$B/proj.jsonl"
touch "$T/release"; wait "$HOLDER" "$UN"; rm -f "$T/held" "$T/release"
check "the folder removed and made again while it waited, a line appended: its own line goes and the new line is kept" "$TWIN" "$(cat "$B/proj.jsonl" 2>/dev/null)"
rm -rf "$B"

# --- the data is kept by folder name: a checkout uninstalled and set up again elsewhere ---
# /old/proj was taken out and the project now lives at /new/proj. --delete-data
# run later in the old checkout must not take the logs, rulings and
# Chief-of-Staff state the new one writes under the same name.
run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; run "$PROJ" uninstall.sh >/dev/null 2>&1
mkdir -p "$T/moved"; project "$T/moved/proj"
run "$T/moved/proj" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; check "the same project set up at a new path" 0 $?
mkdir -p "$HOME/.claude/hook-fire-log" "$HOME/.claude/rulings" "$HOME/.commandeck/chief-of-staff" "$B"; mine live "$T/moved/proj" > "$B/proj.jsonl"
echo '{}' > "$HOME/.claude/hook-fire-log/proj.2026-10-12.jsonl"; echo '{}' > "$HOME/.claude/rulings/proj.jsonl"; echo x > "$HOME/.commandeck/chief-of-staff/proj.state"
run "$PROJ" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1; check "deleting the old checkout's data succeeds" 0 $?
check "and leaves the live project's log, rulings, Chief-of-Staff state and finished-builds record" "1 1 1 1" \
  "$(ls "$HOME/.claude/hook-fire-log" | grep -c '^proj\.') $(ls "$HOME/.claude/rulings" | grep -c '^proj\.jsonl$') $(ls "$HOME/.commandeck/chief-of-staff" | grep -c '^proj\.') $(ls "$B" | grep -c '^proj\.jsonl$')"
check "it says whose they are" 1 "$(grep -c "kept: .*$T/moved/proj" "$T/uninstall.out")"
run "$T/moved/proj" uninstall.sh --delete-data >/dev/null 2>&1
check "the live project's own uninstall does delete them" "0 0" "$(ls "$HOME/.claude/rulings" 2>/dev/null | grep -c '^proj\.jsonl$') $(ls "$B" 2>/dev/null | grep -c '^proj\.jsonl$')"

# --- a folder name with a letter outside ASCII ---
# The merge and the dashboard name the record with one dash for that letter (hooks/lib/project.sh), however many
# bytes it is; uninstall must delete under that same name, or the record is silently left behind.
mkdir -p "$T/uni"; project "$T/uni/projé"
run "$T/uni/projé" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1; check "a project whose name has a letter outside ASCII is set up" 0 $?
UNI=$(. "$PLUGIN/hooks/lib/project.sh"; pp_project "$T/uni/projé"; printf '%s' "$PP_PROJECT")
mkdir -p "$B" "$HOME/.claude/rulings"; mine a "$T/uni/projé" > "$B/$UNI.jsonl"; echo '{}' > "$HOME/.claude/rulings/$UNI.jsonl"
run "$T/uni/projé" uninstall.sh --delete-data >"$T/uninstall.out" 2>&1
check "its finished-builds record and rulings go, under the name the merge writes them by" "no no" \
  "$([ -e "$B/$UNI.jsonl" ] && echo yes || echo no) $([ -e "$HOME/.claude/rulings/$UNI.jsonl" ] && echo yes || echo no)"

[ "$FAIL" = 0 ] || { echo "--- last setup output"; tail -15 "$T/setup.out"; echo "--- last uninstall output"; tail -15 "$T/uninstall.out"; }
done_tests

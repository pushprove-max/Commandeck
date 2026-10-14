#!/usr/bin/env bash
# install-lib.sh -- sourced after paths.sh by setup.sh, uninstall.sh, update.sh
# and doctor.sh. The one home for the install manifest and for what the plugin
# adds to files it does not own.
#
# The manifest is what makes uninstall exact. Before setup changes a path it
# records, under ~/.commandeck/install, what was there: the content's sha256
# (the bytes kept beside it in blobs/), "dangling link" or "did not exist". A project's paths go
# in <project slug>.json, the machine's in _machine.json, shared by every
# project set up here and gone with the last. Two kinds of path:
#   own    the plugin wrote the whole file (its config, a job file)
#   merge  the file is the owner's or another tool's; the plugin added entries
#   dir    a folder setup had to make
# Uninstall takes the plugin's entries back out of a merge file, and only then
# compares: the same content as before gets the prior bytes back, anything else
# was edited since setup and is left as it is and named.
IL_DIR=$HOME/.commandeck/install
IL_PROJECT=$IL_DIR/$PP_MAIN_SLUG.json
IL_MACHINE=$IL_DIR/_machine.json
IL_ROOT=$(cd "$PP_SCRIPTS/.." && pwd)
IL_VERSION=1   # the config schema this plugin writes and reads; there is no migration
IL_CONFIG=$PP_MAIN/.claude/commandeck.json
IL_CODEX=${CODEX_HOME:-$HOME/.codex}
IL_OURS=/hooks/codex-dispatch.sh   # the one command the plugin's Codex entries run
# An entry is the plugin's when its command STARTS as the template's does. A
# hook of the owner's that only mentions the path (a comment, an argument) is
# the owner's: never rewritten, removed or counted. codex-hook-trust.py OURS is the same rule.
IL_OURS_RE="^S=([^ ;']*|'.*')/hooks/codex-dispatch[.]sh; "
# il_shq <path> -- the path as one shell word: as it is when plain (the command,
# and so Codex's trust in it, stays what it was), single-quoted otherwise.
il_shq() {
  local q="'\\''"
  if [[ $1 =~ ^[A-Za-z0-9_./-]+$ ]]; then printf '%s' "$1"; else printf "'%s'" "${1//\'/$q}"; fi
}
IL_BEGIN='<!-- commandeck:begin -->' IL_END='<!-- commandeck:end -->'
IL_EXCLUDE=$PP_MAIN/.git/info/exclude
IL_AGENTS=$PP_MAIN/AGENTS.md
# The project's running state: every path a plugin script or hook, or the
# session itself (a build's papers, main's to-do), writes during ordinary
# running. The one list: setup hides these from git, the doctor reports one
# git tracks, and uninstall takes out the lines setup's manifest recorded.
IL_STATE=(.claude/settings.local.json .claude/builder-events.jsonl .claude/metrics/decisions.jsonl .claude/metrics/seat-events.jsonl
  .claude/metrics/subagent-usage.jsonl .claude/metrics/subagent-usage.jsonl.lock .claude/briefs/ .claude/routing-log todo/main-todo.md
  .claude/workflows/test-audit.js)   # setup's copy holds this machine's paths (il_test_audit)

il_sha() { sha256sum < "$1" | cut -d' ' -f1; }

# il_write <path> -- stdin becomes the file, whole or not at all. A link is
# written through, and an existing file keeps its mode. Every write of the
# install goes through here, so this is also where setup learns what it really
# wrote: with IL_WROTE naming a file, each path whose content is new or
# different gets one line there, "created" or "changed", a tab, the path. A
# write of the same bytes is no line. A file, not a variable: half the callers
# are the far end of a pipe.
il_write() {
  local p=$1 t k=created
  [ ! -L "$p" ] || p=$(readlink -f "$p")
  t=$p.new.$$
  { mkdir -p "${p%/*}" && cat > "$t" && { [ ! -e "$p" ] || { k=changed; ! cmp -s "$t" "$p" || k=; chmod --reference="$p" "$t"; }; } && mv -f "$t" "$p"; } \
    || { rm -f "$t"; echo "commandeck: could not write $p" >&2; return 1; }
  [ -z "$k" ] || [ -z "${IL_WROTE:-}" ] || printf '%s\t%s\n' "$k" "$p" >> "$IL_WROTE"
}

# il_record <manifest> <kind> <path>... -- note what is at each path now. A
# path already recorded keeps its first record: a second setup must not take
# the first one's result for "what was there before".
il_record() {
  local m=$1 kind=$2 j p d prior
  shift 2
  mkdir -p "$IL_DIR/blobs" && chmod 700 "$IL_DIR" || return 1
  j=$(cat "$m" 2>/dev/null) && [ -n "$j" ] || j='{"version": 1, "entries": {}}'
  for p; do
    ! jq -e --arg p "$p" '.entries | has($p)' <<<"$j" >/dev/null || continue
    d=${p%/*}
    while [ ! -d "$d" ]; do
      j=$(jq --arg p "$d" '.entries[$p] //= {prior: "did not exist", kind: "dir"}' <<<"$j"); d=${d%/*}
    done
    prior="did not exist"
    # A link to a file not made yet is the owner's: setup writes through it.
    if [ -L "$p" ] && [ ! -e "$p" ]; then prior="dangling link"
    elif [ -e "$p" ]; then prior=$(il_sha "$p") && cp "$p" "$IL_DIR/blobs/$prior" || return 1; prior=sha256:$prior; fi
    j=$(jq --arg p "$p" --arg prior "$prior" --arg k "$kind" '.entries[$p] = {prior: $prior, kind: $k}' <<<"$j")
  done
  il_write "$m" <<<"$j"
}
# il_set <manifest> <jq filter> [jq args] -- change the manifest in place.
il_set() { local m=$1 j; shift; j=$(jq "$@" "$m") && il_write "$m" <<<"$j"; }
# il_has <manifest> <path> -- setup recorded this path.
il_has() { jq -e --arg p "$2" '.entries | has($p)' "$1" >/dev/null 2>&1; }
# il_projects -- every project manifest on this machine, one a line.
il_projects() { find "$IL_DIR" -maxdepth 1 -name '*.json' ! -name '_machine.json' 2>/dev/null | sort; }

# --- what the plugin adds, and how it comes back out ---

# il_allow <root> -- the permission rules a session needs to run the plugin without a prompt per command.
il_allow() {
  jq -cn --arg r "$1" '["Bash(orca-ide orchestration:*)", "Bash(orca-ide terminal:*)", "Bash(orca-ide worktree:*)", "Bash(bash \($r)/scripts/*)"]'
}
# il_allow_set <manifest> <settings file> <rules json> -- the plugin's rules in
# the file become exactly <rules>; the ones it added before are in the manifest.
il_allow_set() {
  local m=$1 f=$2 new=$3 old j added doc
  # No file, or an empty one, is an empty object: jq prints nothing for no input.
  doc=$(cat "$f" 2>/dev/null) || doc=; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  old=$(jq -c --arg p "$f" '.entries[$p].added // []' "$m") || return 1
  # Only what the owner did not already have is the plugin's to take back out.
  added=$(jq -c --argjson old "$old" --argjson new "$new" '$new - ((.permissions.allow // []) - $old)' <<<"$doc" 2>/dev/null) || added=$new
  j=$(jq --argjson old "$old" --argjson new "$new" '
      ((.permissions.allow // []) - $old) as $rest
      | .permissions.allow = $rest + ($new - $rest)
      | if .permissions.allow == [] then del(.permissions.allow) else . end
      | if .permissions == {} then del(.permissions) else . end' <<<"$doc" 2>/dev/null) \
    || { echo "commandeck: $f is not JSON; fix it and run this again" >&2; return 1; }
  il_write "$f" <<<"$j" && il_set "$m" --arg p "$f" --argjson new "$added" '.entries[$p].added = $new'
}

# il_workflows <manifest> <project settings file> [off] -- "enableWorkflows": true
# in the project's settings: Claude Code hides the Workflow tool without it. An
# answer the owner already gave, true or false, is the owner's and stays; "off"
# takes out only a true that setup put there.
il_workflows() {
  local m=$1 f=$2 doc
  doc=$(cat "$f" 2>/dev/null) || doc=; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  if [ "${3:-}" = off ]; then
    jq -e --arg p "$f" '.entries[$p].workflows == true' "$m" >/dev/null 2>&1 && jq -e '.enableWorkflows == true' <<<"$doc" >/dev/null 2>&1 || return 0
    doc=$(jq 'del(.enableWorkflows)' <<<"$doc") && il_write "$f" <<<"$doc"
  elif jq -e 'has("enableWorkflows")' <<<"$doc" >/dev/null 2>&1; then
    jq -e '.enableWorkflows == true' <<<"$doc" >/dev/null || echo "workflows are switched off in $f (\"enableWorkflows\": false), left as it is: /test-audit needs it true"
  else
    doc=$(jq '.enableWorkflows = true' <<<"$doc") && il_write "$f" <<<"$doc" && il_set "$m" --arg p "$f" '.entries[$p].workflows = true'
  fi
}
# il_test_audit <root> <file> -- the project's /test-audit: the plugin's script
# with the two paths it cannot find out written in. A workflow script sees no
# disk and no environment, and its agents type both paths into shell commands.
il_test_audit() {
  jq -Rr --arg p "$1/templates/test-audit-prompt.md" --arg o "$PP_SCRATCH" '
    if startswith("const PROMPT = ") then "const PROMPT = \($p | tojson)"
    elif startswith("const OUT_ROOT = ") then "const OUT_ROOT = \($o | tojson)" else . end' "$1/templates/test-audit.js" | il_write "$2"
}

# il_codex_hooks <root> -- Codex's hooks.json with the plugin's five entries
# pointing at <root>. An entry already there is re-pointed where it stands and a
# new one goes last in its event: another tool's entries keep their positions,
# which is what Codex keys their trust by. No root takes the entries out.
il_codex_hooks() {
  local f=$IL_CODEX/hooks.json j
  [ -s "$f" ] || { [ -n "$1" ] || return 0; echo '{}' | il_write "$f" || return 1; }
  if [ -n "$1" ]; then
    j=$(jq --arg m "$IL_OURS_RE" --arg r "$(il_shq "$1")" --slurpfile t "$IL_ROOT/templates/codex-hooks.json" '
        def ours: (.command // "") | test($m);
        ($t[0].hooks | walk(if type == "string" then gsub("__PLUGIN_ROOT__"; $r) else . end)) as $th
        | .hooks = reduce ($th | keys_unsorted[]) as $e (.hooks // {};
            if any(.[$e][]?.hooks[]?; ours)
            then .[$e] |= map(.hooks |= map(if ours then . + $th[$e][0].hooks[0] else . end))
            else .[$e] = (.[$e] // []) + $th[$e] end)' "$f")
  else
    j=$(jq --arg m "$IL_OURS_RE" '
        .hooks |= with_entries(.value |= map(.hooks |= map(select((.command // "") | test($m) | not)) | select(.hooks != [])) | select(.value != []))
        | if .hooks == {} then del(.hooks) else . end' "$f")
  fi || { echo "commandeck: $f is not JSON; fix it and run this again" >&2; return 1; }
  il_write "$f" <<<"$j"
}
# il_codex_count [root] -- how many of the plugin's entries Codex has (pointing at <root>, when given).
il_codex_count() {
  jq --arg m "$IL_OURS_RE" --arg r "${1:+S=$(il_shq "$1")$IL_OURS; }" '[.hooks[]?[]?.hooks[]? | select((.command // "") | test($m) and startswith($r))] | length' "$IL_CODEX/hooks.json" 2>/dev/null || echo 0
}

# il_notify <root> -- Codex's one `notify` line. It is set only when the owner
# has none: Codex takes a single notify command, and theirs stays. A top-level
# key must sit above the first table, so the line goes first.
# The path is a TOML string: jq writes it as a JSON one, which TOML reads the same.
il_notify_line() { printf 'notify = [%s]\n' "$(jq -n --arg p "$1/hooks/codex-notify.sh" '$p')"; }
il_notify() {
  local f=$IL_CODEX/config.toml rest
  [ -e "$f" ] || { [ -n "$1" ] || return 0; : | il_write "$f" || return 1; }
  rest=$(grep -vE '^notify = \[".*/hooks/codex-notify\.sh"\]$' "$f" || true)
  [ -z "$1" ] || grep -qE '^[[:space:]]*notify[[:space:]]*=' <<<"$rest" || rest=$(il_notify_line "$1")${rest:+$'\n'$rest}
  [ "$rest" = "$(cat "$f")" ] || printf '%s\n' "$rest" | il_write "$f"
}

# il_block <file> [text file] -- the plugin's marked block in an instruction
# file: replaced by <text file>'s content, or taken out when none is given.
il_block() {
  local f=$1 body=''
  [ ! -e "$f" ] || body=$(awk -v b="$IL_BEGIN" -v e="$IL_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$f")
  if [ -n "${2:-}" ]; then
    { [ -z "$body" ] || printf '%s\n\n' "$body"; printf '%s\n' "$IL_BEGIN"; cat "$2"; printf '%s\n' "$IL_END"; } | il_write "$f"
  elif [ -e "$f" ] && [ "$body" != "$(cat "$f")" ]; then
    printf '%s\n' "$body" | il_write "$f"
  fi
}

# il_lines <manifest> <file> [line...] -- the plugin's own lines in a line-list
# file (git's exclude list) become exactly these, each added once at the end.
il_lines() {
  local m=$1 f=$2 old l body
  shift 2
  old=$(jq -r --arg p "$f" '.entries[$p].added // [] | .[]' "$m") || return 1
  body=$(cat "$f" 2>/dev/null || true)
  [ -z "$old" ] || body=$(grep -vxFf <(printf '%s\n' "$old") <<<"$body" || true)
  old='[]'
  for l; do
    grep -qxF -- "$l" <<<"$body" && continue
    body+=${body:+$'\n'}$l; old=$(jq -c --arg l "$l" '. + [$l]' <<<"$old")
  done
  [ -e "$f" ] || [ -n "$body" ] || return 0
  printf '%s\n' "$body" | il_write "$f" && il_set "$m" --arg p "$f" --argjson a "$old" '.entries[$p].added = $a'
}

# --- putting a manifest's paths back ---

# il_same <file> <prior bytes> -- the same content, whatever the formatting:
# JSON by value, text but for blank lines at the end.
il_same() {
  case $1 in
    *.json) [ "$(jq -S . "$1" 2>/dev/null || echo a)" = "$(jq -S . "$2" 2>/dev/null || echo b)" ] ;;
    *) [ "$(perl -0pe 's/\s+\z//' "$1")" = "$(perl -0pe 's/\s+\z//' "$2")" ] ;;
  esac
}
# il_empty <file> -- nothing of anyone's is left in a merge file the plugin created.
il_empty() {
  case $1 in *.json) jq -e '. == {}' "$1" >/dev/null 2>&1 ;; *) ! grep -q '[^[:space:]]' "$1" ;; esac
}
# il_restore <manifest> -- every recorded path back to what the manifest says
# was there, then the manifest itself. Run it after the plugin's entries are
# out of the merge files. Prints one line per path it had to leave.
il_restore() {
  local m=$1 kind prior p blob
  while IFS=$'\t' read -r kind prior p; do
    blob=$IL_DIR/blobs/${prior#sha256:}
    if [ "$prior" = "dangling link" ]; then
      # What setup wrote through the link goes; the link stays as it was.
      [ -L "$p" ] && [ -e "$p" ] || continue
      if [ "$kind" = own ] || il_empty "$p"; then rm -f "$(readlink -f "$p")"
      else echo "changed since setup, left as it is: $p"; fi
    elif [ "$prior" = "did not exist" ]; then
      [ -e "$p" ] || continue
      if [ "$kind" = own ] || il_empty "$p"; then rm -f "$p"
      else echo "changed since setup, left as it is: $p"; fi
    elif [ ! -s "$blob" ] && [ "$prior" != "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
      echo "the bytes setup kept for $p are gone ($blob), left as it is: $p"
    elif [ ! -e "$p" ] || [ "$kind" = own ] || il_same "$p" "$blob"; then
      [ -e "$p" ] && [ "$(il_sha "$p")" = "${prior#sha256:}" ] || il_write "$p" < "$blob"
    else echo "changed since setup, left as it is: $p"; fi
  done < <(jq -r '.entries | to_entries[] | select(.value.kind != "dir") | [.value.kind, .value.prior, .key] | @tsv' "$m")
  # The folders setup made, deepest first; one that now holds something stays.
  jq -r '.entries | to_entries[] | select(.value.kind == "dir") | .key' "$m" | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- \
    | while IFS= read -r p; do rmdir "$p" 2>/dev/null || true; done
  rm -f "$m"
}

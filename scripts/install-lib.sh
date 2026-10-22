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
# The real folder, not the stable link: setup run through the link would point the link at itself.
IL_ROOT=$(cd "$PP_SCRIPTS/.." && pwd -P)
# A path that outlives a session (a checkpoint, a notify wrapper) names the plugin
# by this link, never by its versioned cache folder: setup points it at IL_ROOT.
IL_LINK=$HOME/.commandeck/plugin
IL_VERSION=1   # the config schema this plugin writes and reads; there is no migration
IL_CONFIG=$PP_MAIN/.claude/commandeck.json
IL_CODEX=${CODEX_HOME:-$HOME/.codex}
# A relative CODEX_HOME is the folder it names from here: the manifest key must name it from any later cwd.
case $IL_CODEX in /*) ;; *) IL_CODEX=$(cd "$IL_CODEX" 2>/dev/null && pwd -P) || IL_CODEX=$PWD/${CODEX_HOME#./} ;; esac
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
IL_GLOBAL=$HOME/.claude/CLAUDE.md   # the owner's own instructions: the plugin adds only marked blocks (il_global)
# Setup's visible copy of an owner's file it is about to change (il_backup) is the owner's to keep or
# delete, never git's: the first entry below.
# The project's running state: every path a plugin script or hook, or the
# session itself (a build's papers, main's to-do), writes during ordinary
# running. The one list: setup hides these from git, the doctor reports one
# git tracks, and uninstall takes out the lines setup's manifest recorded.
IL_STATE=('*.commandeck-bak-*' .claude/settings.local.json .claude/builder-events.jsonl .claude/metrics/decisions.jsonl .claude/metrics/seat-events.jsonl
  .claude/metrics/unit-ledger.jsonl .claude/metrics/subagent-usage.jsonl .claude/metrics/subagent-usage.jsonl.lock .claude/briefs/ .claude/routing-log todo/main-todo.md
  .claude/workflows/test-audit.js)   # setup's copy holds this machine's paths (il_test_audit)

il_sha() { sha256sum < "$1" | cut -d' ' -f1; }

# IL_PLAN (setup.sh --plan): nothing is written. il_write prints what it would
# write (a new file by its length, a changed one as a diff) and still notes it in
# IL_WROTE, keeping the content beside it (il_shadow), so a later step of the
# plan reads what an earlier one would have written (il_cat), as apply does;
# il_record and il_set change no manifest.
il_shadow() { printf '%s.%s' "${IL_WROTE:-/dev/null}" "$(printf %s "$1" | cksum | cut -d' ' -f1)"; }
# il_cat <path> -- the file as setup has it so far: in a plan, what il_write would have made it.
il_cat() {
  local p=$1 s
  [ ! -L "$p" ] || p=$(readlink -f "$p")
  s=$(il_shadow "$p")
  if [ -n "${IL_PLAN:-}" ] && [ -n "${IL_WROTE:-}" ] && [ -e "$s" ]; then cat "$s"; else cat "$p"; fi
}
# il_read <path> -- il_cat for a step that writes what it read back: no file is nothing, but one that is there and
# cannot be read fails, with a line. Read as empty, the owner's whole file was written over with setup's few keys.
il_read() {
  il_cat "$1" 2>/dev/null && return 0
  [ ! -e "$1" ] || { echo "commandeck: $1 is there but cannot be read; fix its permissions and run this again" >&2; return 1; }
}
# il_write <path> -- stdin becomes the file, whole or not at all. A link is
# written through, and an existing file keeps its mode. Every write of the
# install goes through here, so this is also where setup learns what it really
# wrote: with IL_WROTE naming a file, each path whose content is new or
# different gets one line there, "created" or "changed", a tab, the path. A
# write of the same bytes is no line. A file, not a variable: half the callers
# are the far end of a pipe.
il_write() {
  local p=$1 t s k=created
  [ ! -L "$p" ] || p=$(readlink -f "$p")
  if [ -n "${IL_PLAN:-}" ]; then
    t=$(mktemp) && cat > "$t" || return 1
    s=$(il_shadow "$p")
    # A second change to one path was made from the first (il_cat): shown as a change to that.
    if [ -n "${IL_WROTE:-}" ] && [ -e "$s" ]; then k=changed
      cmp -s "$s" "$t" || { echo "plan: and, on top of the change above, $p:"
        { diff -u --label "$p (planned above)" --label "$p (after setup)" "$s" "$t" || true; } | sed 's/^/    /'; }
    elif [ ! -e "$p" ]; then k=created; echo "plan: would create $p ($(wc -l < "$t" | tr -d ' ') lines)"
      [ "$(wc -l < "$t")" -gt 30 ] || sed 's/^/    +/' "$t"
    elif cmp -s "$t" "$p"; then k=
    else k=changed; echo "plan: would change $p:"; { diff -u --label "$p (now)" --label "$p (after setup)" "$p" "$t" || true; } | sed 's/^/    /'; fi
    [ -z "$k" ] || [ -z "${IL_WROTE:-}" ] || { printf '%s\t%s\n' "$k" "$p" >> "$IL_WROTE"; cp "$t" "$s"; }
    rm -f "$t"
    return 0
  fi
  t=$p.new.$$
  { mkdir -p "$(dirname -- "$p")" && cat > "$t" && { [ ! -e "$p" ] || { k=changed; ! cmp -s "$t" "$p" || k=; chmod --reference="$p" "$t"; }; } && mv -f "$t" "$p"; } \
    || { rm -f "$t"; echo "commandeck: could not write $p" >&2; return 1; }
  [ -z "$k" ] || [ -z "${IL_WROTE:-}" ] || printf '%s\t%s\n' "$k" "$p" >> "$IL_WROTE"
}

# il_record <manifest> <kind> <path>... -- note what is at each path now. A
# path already recorded keeps its first record: a second setup must not take
# the first one's result for "what was there before".
il_record() {
  local m=$1 kind=$2 j p d prior
  shift 2
  [ -z "${IL_PLAN:-}" ] || return 0
  mkdir -p "$IL_DIR/blobs" && chmod 700 "$IL_DIR" || return 1
  j=$(cat "$m" 2>/dev/null) && [ -n "$j" ] || j='{"version": 1, "entries": {}}'
  for p; do
    # A relative key an older setup left is never taken for this path: the cwd it was written in is in no manifest,
    # so read from here it can name another project's file (il_drop_relative_keys).
    ! jq -e --arg p "$p" '.entries | has($p)' <<<"$j" >/dev/null || continue
    # dirname, not ${p%/*}: a path with no / (or under a missing top folder) stays itself and never ended the loop.
    d=$(dirname -- "$p")
    while [ ! -d "$d" ]; do
      j=$(jq --arg p "$d" '.entries[$p] //= {prior: "did not exist", kind: "dir"}' <<<"$j"); d=$(dirname -- "$d")
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
il_set() { local m=$1 j; shift; [ -z "${IL_PLAN:-}" ] || return 0; j=$(jq "$@" "$m") && il_write "$m" <<<"$j"; }
# il_has <manifest> <path> -- setup recorded this path.
il_has() { jq -e --arg p "$2" '.entries | has($p)' "$1" >/dev/null 2>&1; }
# il_projects -- every project manifest on this machine, one a line. None yet (no install folder, as in a first
# setup --plan) is an empty list, not a failure: under pipefail find's error failed setup's routing step.
il_projects() { [ ! -d "$IL_DIR" ] || find "$IL_DIR" -maxdepth 1 -name '*.json' ! -name '_machine.json' 2>/dev/null | sort; }

# --- what the plugin adds, and how it comes back out ---

# il_allow <root> -- the permission rules a session needs to run the plugin without a prompt per command.
il_allow() {
  jq -cn --arg r "$1" --arg l "$IL_LINK" '["Bash(orca-ide orchestration:*)", "Bash(orca-ide terminal:*)", "Bash(orca-ide worktree:*)", "Bash(bash \($r)/scripts/*)", "Bash(bash \($l)/scripts/*)"]'
}
# il_allow_set <manifest> <settings file> <rules json> -- the plugin's rules in
# the file become exactly <rules>; the ones it added before are in the manifest.
il_allow_set() {
  local m=$1 f=$2 new=$3 old j added doc
  # No file, or an empty one, is an empty object: jq prints nothing for no input.
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  old=$( { cat "$m" 2>/dev/null || echo '{}'; } | jq -c --arg p "$f" '.entries[$p].added // []') || return 1
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

# il_routing_merged <file> <defaults> -- a routing file of the owner's own (COMMANDECK_ROUTING) with each role the
# defaults have and it lacks added from the defaults; a role it has stays as it is. Writes nothing, and prints
# nothing for the defaults file itself or a file that does not exist.
il_routing_merged() {
  [ -f "$1" ] && ! [ "$1" -ef "$2" ] || return 0
  jq --slurpfile d "$2" '(.roles // {}) as $r | .roles = $r + ($d[0].roles | with_entries(select(.key as $k | $r | has($k) | not)))' "$1"
}
# il_abs <path> [base] -- the path absolute, a relative one taken from <base> (default here) with its folder's links
# resolved; an absolute one as it is. A manifest key names its file from any cwd.
il_abs() {
  case $1 in /*) printf '%s\n' "$1" ;;
    *) (cd "${2:-.}" && cd "$(dirname -- "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "${1##*/}") || printf '%s/%s\n' "${2:-$PWD}" "$1" ;; esac
}
# il_drop_relative_keys <manifest> <where> [what] -- drops each relative key an older setup recorded (a
# COMMANDECK_ROUTING of ../x, a CODEX_HOME of .codex), and says so: that setup's cwd went unrecorded, and every folder
# it could have been names another file for some layout. What it added stays in, and no bytes are put back at a
# guessed path.
il_drop_relative_keys() {
  local k
  [ -s "$1" ] || return 0
  jq -r '.entries | keys[] | select(startswith("/") | not)' "$1" | while IFS= read -r k; do
    echo "an older setup recorded ${3:-a routing file} as $k, relative to a folder it did not record; that file is left as it is, with what setup added to it ($2)"
    il_set "$1" --arg k "$k" 'del(.entries[$k])' || return 1
  done
}
# il_routing_others <manifest> <file> [maybe] -- each role every other project's manifest records for <file>, with
# every value any of them recorded for it ({role: [values]}: one record must not hide another's), under an
# absolute key of the same file (another spelling, a ./ or a symlink, compared as files): proof it is that file. maybe:
# also under every relative key an older setup left, whatever its name, since nothing proves which file it names.
il_routing_others() {
  local o k
  il_projects | while IFS= read -r o; do
    [ "$o" -ef "$1" ] && continue
    jq -r '.entries | to_entries[] | select(.value.roles) | .key' "$o" 2>/dev/null | while IFS= read -r k; do
      case $k in /*) [ "$k" -ef "$2" ] ;; *) [ -n "${3:-}" ] ;; esac || continue
      jq -c --arg p "$k" '.entries[$p].roles' "$o"
    done
  done | jq -cs 'reduce (.[] | to_entries[]) as $e ({}; .[$e.key] += [$e.value])'
}
# il_routing_seats <manifest> <file> <merged doc file> [off] -- setup: the file becomes the merged doc when that
# adds a role, and the manifest records each added role under .entries[<file>].roles, merged into what an earlier
# setup recorded, with each role of the file another project's setup added and records under the same file (one
# routing file, two projects). off: takes out each recorded role whose value is still what setup added and that no
# other project's record could share, and says which it kept and why; one the owner changed since stays, as does
# every role of the owner's own. il_restore's merge rule then does the rest.
il_routing_seats() {
  local m=$1 f=$2 add doc shared maybe
  shared=$(il_routing_others "$m" "$f") || return 1
  if [ "${4:-}" = off ]; then
    [ -e "$f" ] || return 0
    maybe=$(il_routing_others "$m" "$f" maybe) || return 1
    jq -r --arg p "$f" --argjson s "$shared" --argjson y "$maybe" '.entries[$p].roles // {} | to_entries
      | ([.[] | select(.value as $v | any($s[.key][]?; . == $v)) | .key],
         [.[] | select(.value as $v | any($s[.key][]?; . == $v) | not) | select(.value as $v | any($y[.key][]?; . == $v)) | .key])
      | join(", ")' "$m" | { IFS= read -r a; IFS= read -r b
      [ -z "$a" ] || echo "kept seats $a in $f: another project's install record names this file"
      [ -z "$b" ] || echo "kept seats $b in $f: an older setup's install record in another project names a routing file by a relative path, which may be this one"; }
    add=$(jq -c --arg p "$f" --argjson s "$maybe" '.entries[$p].roles // {} | with_entries(select(.value as $v | any($s[.key][]?; . == $v) | not))' "$m") || return 1
    doc=$(jq --argjson a "$add" '.roles |= with_entries(select(.key as $k | .value as $v | ($a | has($k)) and $a[$k] == $v | not))' "$f" 2>/dev/null) \
      || { echo "commandeck: $f is not JSON; the seats setup added to it are left in" >&2; return 0; }
    il_write "$f" <<<"$doc"; return
  fi
  shared=$(jq -c --argjson s "$shared" '.roles // {} | with_entries(select(.value as $v | any($s[.key][]?; . == $v)))' "$f") || return 1
  add=$(jq -c --slurpfile o "$f" '.roles | with_entries(select(.key as $k | $o[0].roles // {} | has($k) | not))' "$3") || return 1
  if [ "$add" != '{}' ]; then
    il_record "$m" merge "$f" && il_write "$f" < "$3" || return 1
    echo "Routing: added seats $(jq -r 'keys_unsorted | join(", ")' <<<"$add") to $f from the plugin's defaults; uninstall takes them out again."
  fi
  [ "$add$shared" != '{}{}' ] || return 0
  il_set "$m" --arg p "$f" --argjson a "$add" --argjson s "$shared" '.entries[$p].roles = (.entries[$p].roles // {}) + $s + $a'
}

# il_workflows <manifest> <project settings file> [off] -- "enableWorkflows": true
# in the project's settings: Claude Code hides the Workflow tool without it. An
# answer the owner already gave, true or false, is the owner's and stays; "off"
# takes out only a true that setup put there.
il_workflows() {
  local m=$1 f=$2 doc
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  if [ "${3:-}" = off ]; then
    jq -e --arg p "$f" '.entries[$p].workflows == true' "$m" >/dev/null 2>&1 && jq -e '.enableWorkflows == true' <<<"$doc" >/dev/null 2>&1 || return 0
    doc=$(jq 'del(.enableWorkflows)' <<<"$doc") && il_write "$f" <<<"$doc"
  elif jq -e 'has("enableWorkflows")' <<<"$doc" >/dev/null 2>&1; then
    jq -e '.enableWorkflows == true' <<<"$doc" >/dev/null || echo "workflows are switched off in $f (\"enableWorkflows\": false), left as it is: /test-audit needs it true"
  else
    doc=$(jq '.enableWorkflows = true' <<<"$doc") && il_write "$f" <<<"$doc" && il_set "$m" --arg p "$f" '.entries[$p].workflows = true'
  fi
}
# il_advisor_off <manifest> <settings file> [off] -- the orchestrator is the owner's own claude, started by
# no launch template, so its routing's "no advisor" lives in the project's settings: Claude Code's one off
# switch (#85). A value the owner set is left as it is. shortcut: a project that commits this file hands
# the switch to its worktrees too, where a seat that names an advisor would lose it; none does by default.
il_advisor_off() {
  local m=$1 f=$2 doc
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  if [ "${3:-}" = off ]; then
    jq -e --arg p "$f" '.entries[$p].advisorOff == true' "$m" >/dev/null 2>&1 || return 0
    doc=$(jq 'del(.env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL) | if .env == {} then del(.env) else . end' <<<"$doc") && il_write "$f" <<<"$doc"
  elif ! jq -e '(.env // {}) | has("CLAUDE_CODE_DISABLE_ADVISOR_TOOL")' <<<"$doc" >/dev/null 2>&1; then
    doc=$(jq '.env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL = "1"' <<<"$doc") && il_write "$f" <<<"$doc" && il_set "$m" --arg p "$f" '.entries[$p].advisorOff = true'
  fi
}
# il_cache_ttl <manifest> <settings file> [off] -- prompt-cache lifetimes: 5 minutes for the main conversation and
# subagents (measured 2026-10-18 on real transcripts: 5 minutes cost main about 5% less than 1 hour, because panes
# seldom pause 5 to 60 minutes). A key the owner set is left as it is; a value setup itself wrote earlier (a 1 hour
# of 0.14) is replaced; off takes out only a value setup wrote and nobody changed since.
il_cache_ttl() {
  local m=$1 f=$2 doc s r
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  if [ "${3:-}" = off ]; then
    s=$(jq -c --arg p "$f" '.entries[$p].cacheTtl // {}' "$m" 2>/dev/null) || s='{}'
    [ "$s" != '{}' ] || return 0
    doc=$(jq --argjson s "$s" 'reduce ($s | to_entries[]) as $e (.; if .[$e.key] == $e.value then del(.[$e.key]) else . end)' <<<"$doc") \
      && il_write "$f" <<<"$doc" && il_set "$m" --arg p "$f" 'del(.entries[$p].cacheTtl)'
  else
    r=$(jq -c --arg p "$f" '.entries[$p].cacheTtl // {}' "$m" 2>/dev/null) || r='{}'
    s=$(jq -c '{promptCacheTtl: "5m", subagentPromptCacheTtl: "5m"} | with_entries(select(.key as $k | ($d | has($k) | not) or $d[$k] == $r[$k]))' --argjson d "$doc" --argjson r "$r" -n)
    [ "$s" != '{}' ] || return 0
    doc=$(jq --argjson s "$s" '. + $s' <<<"$doc") && il_write "$f" <<<"$doc" \
      && il_set "$m" --arg p "$f" --argjson s "$s" '.entries[$p].cacheTtl = ((.entries[$p].cacheTtl // {}) + $s)'
  fi
}
# il_cuts <cuts json> <flag> <answer> -- setup's worker cuts (workerSkillsOff, workerPluginsOff, keeps) with one answer
# applied, printed. --worker-skills-off takes skill names and --worker-plugins-off plugin@marketplace keys, each a comma
# list ('' clears it); --keep-word takes <word>=<names>, a name with an @ a plugin, and <word>= drops the word. Every
# name is the owner's: the plugin ships none. An answer it cannot take is refused, and nothing is printed.
il_cuts() {
  local s='[A-Za-z0-9_.:-]+' p='[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+' v=$3 w= k re what
  case $2 in
    --worker-skills-off) k=workerSkillsOff re=$s what="skill names" ;;
    --worker-plugins-off) k=workerPluginsOff re=$p what="plugin@marketplace keys" ;;
    *) k=keeps re="$p|$s" what="<word>=<skill or plugin@marketplace>[,...], a word other than all"
       [[ $v =~ ^([A-Za-z0-9_-]+)=(.*)$ ]] && [ "${BASH_REMATCH[1]}" != all ] && w=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]} ;;
  esac
  [ "$k" != keeps ] || [ -n "$w" ] && [[ $v =~ ^(($re)(,($re))*)?$ ]] \
    || { echo "setup: $2 takes $what, separated by commas, not '$3'. Nothing was changed" >&2; return 1; }
  jq -c --arg k "$k" --arg w "$w" --arg v "$v" '($v | split(",") | unique) as $n
    | if $k != "keeps" then (if $n == [] then del(.[$k]) else .[$k] = $n end)
      elif $n == [] then del(.keeps[$w]) | if .keeps == {} then del(.keeps) else . end
      else .keeps[$w] = {skills: ($n | map(select(contains("@") | not))), plugins: ($n | map(select(contains("@"))))} end' <<<"$1"
}
# il_auto_mode <manifest> <settings file> add|leave|remove -- two plain-English lines in Claude Code's
# auto-mode classifier environment list (the classifier ignores autoMode in a project's settings, so the owner's
# user file is its home): the plugin's repo and scripts, and the relay pane. The list keeps "$defaults" (the
# built-in rules). A list the owner wrote without it replaced those rules on purpose: left as it is, and said.
# leave changes nothing, in the file or the manifest (the manifest serves every project on this machine);
# remove takes out only the lines setup recorded, and the list too when setup made it.
il_auto_mode() {
  local m=$1 f=$2 doc new how rec
  case $3 in
    leave) return 0 ;;
    add)
      doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
      new=$(jq -cn --arg h "$(jq -r '.homepage // empty' "$IL_ROOT/.claude-plugin/plugin.json")" --arg l "$IL_LINK" '[
        "Trusted repo: \($h) (the Commandeck workflow plugin). Its scripts and hooks under \($l) are this workflow'"'"'s own tools, run by every pane.",
        "Key internal services: Orca panes on this machine. The relay pane (the worktree ending in /Chief-of-Staff) passes the owner'"'"'s answers to main word for word; main checks each against the owner'"'"'s ruling log before acting."]')
      how=$(jq -r '(.autoMode.environment // null) as $e | if $e == null then "new" elif ($e | type) == "array" and any($e[]; . == "$defaults") then "append" else "refuse" end' <<<"$doc" 2>/dev/null) \
        || { echo "commandeck: $f is not JSON; fix it and run this again" >&2; return 1; }
      if [ "$how" = refuse ]; then
        echo "auto mode: the environment list in $f has no \"\$defaults\", so it replaces Claude Code's built-in list; left as it is. To keep the built-in rules and add this plugin's lines, add \"\$defaults\" to the list and run setup again"
        return 0
      fi
      new=$(jq -c --argjson d "$doc" '$d.autoMode.environment as $e | . - ($e // [])' <<<"$new")
      [ "$new" != '[]' ] || return 0
      il_record "$m" merge "$f" || return 1
      doc=$(jq --argjson n "$new" '.autoMode.environment = ((.autoMode.environment // ["$defaults"]) + $n)' <<<"$doc") && il_write "$f" <<<"$doc" \
        && il_set "$m" --arg p "$f" --argjson n "$new" --arg how "$how" '.entries[$p].autoMode = {created: ((.entries[$p].autoMode.created // false) or $how == "new"), added: ((.entries[$p].autoMode.added // []) + $n)}' ;;
    remove)
      rec=$(jq -c --arg p "$f" '.entries[$p].autoMode // empty' "$m" 2>/dev/null); [ -n "$rec" ] || return 0
      doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
      doc=$(jq --argjson r "$rec" 'if (.autoMode.environment | type) == "array" then
          .autoMode.environment -= $r.added
          | (if $r.created and .autoMode.environment == ["$defaults"] then del(.autoMode.environment) else . end)
          | (if .autoMode == {} then del(.autoMode) else . end) else . end' <<<"$doc") \
        && il_write "$f" <<<"$doc" && il_set "$m" --arg p "$f" 'del(.entries[$p].autoMode)' ;;
  esac
}
# il_auto_mode_report -- the doctor's lines on the auto-mode classifier's lists, each "ok <why>" or "warn <what is
# wrong and the fix>". A list in ~/.claude/settings.json without "$defaults" replaced Claude Code's built-in one;
# the classifier ignores autoMode in a project's settings files.
il_auto_mode_report() {
  local f=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json k n=0 where="see what it uses: claude auto-mode config, claude auto-mode critique, and /permissions \"Recently denied\""
  for k in environment allow soft_deny hard_deny; do
    jq -e --arg k "$k" '.autoMode[$k] | type == "array" and all(.[]; . != "$defaults")' "$f" >/dev/null 2>&1 || continue
    n=$((n+1)); echo "warn auto mode: the $k list in $f has no \"\$defaults\", so it replaces Claude Code's built-in $k rules; add \"\$defaults\" to keep them ($where)"
  done
  for f in "$PP_MAIN/.claude/settings.json" "$PP_MAIN/.claude/settings.local.json"; do
    jq -e 'has("autoMode")' "$f" >/dev/null 2>&1 || continue
    n=$((n+1)); echo "warn auto mode: $f has autoMode, which the classifier ignores there; move it to ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json ($where)"
  done
  [ "$n" != 0 ] || echo "ok auto mode: no list of yours replaces the built-in rules, and no project file carries autoMode"
}
# il_shadow_report -- the doctor's lines on the main checkout's .claude/settings.local.json, each "ok <why>" or "warn
# <what is wrong and the fix>". Claude Code applies that file over a worktree's own for the same key, so a key there
# beats the per-worktree one worktree-setup.sh wrote. For every scalar leaf the script writes for a Builder (a worker's
# leaves are a subset) and for the relay, the file's different value is a warning. Array entries merge across files, so
# they are not compared. The profiles come from throwaway worktrees; the owner's file is reported, never edited.
il_shadow_report() {
  local ml=$PP_MAIN/.claude/settings.local.json t k mv wv n=0 w bad=0
  [ -f "$ml" ] || { echo "ok settings: no .claude/settings.local.json in the main checkout, so nothing shadows a worktree's own"; return 0; }
  t=$(mktemp -d)
  for w in Builder-probe Chief-of-Staff; do
    git -C "$PP_MAIN" worktree add -q --detach --no-checkout "$t/$w" 2>/dev/null || { bad=1; continue; }
    (cd "$t/$w" && bash "$PP_SCRIPTS/worktree-setup.sh" "$t/$w" --builder --print-settings 2>/dev/null) > "$t/$w.json" || { bad=1; : > "$t/$w.json"; }
    git -C "$PP_MAIN" worktree remove --force "$t/$w" 2>/dev/null
  done
  while IFS=$'\t' read -r k mv wv; do
    n=$((n+1))
    if [ "$k" = env.CLAUDE_CODE_PROMPT_CACHE_TTL ]; then
      echo "warn prompt cache: $ml sets CLAUDE_CODE_PROMPT_CACHE_TTL=$mv, and Claude Code applies that file over every worktree's own settings, so the relay and worker panes run $mv; move the key to ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    else
      echo "warn settings: $ml sets $k=$mv, and Claude Code applies that file over every worktree's own settings, so a worker pane runs $mv where setup writes $wv; remove the key from that file"
    fi
  done < <(for w in Builder-probe Chief-of-Staff; do [ ! -s "$t/$w.json" ] || jq -r --slurpfile m "$ml" '
      . as $p | [paths(scalars | true) | select(all(.[]; type == "string"))][] as $k
      | ((try ($m[0] | getpath($k)) catch null)) as $mv
      | select($mv != null and ($mv | type) != "object" and $mv != ($p | getpath($k)))
      | [($k | join(".")), ($mv | tostring), ($p | getpath($k) | tostring)] | @tsv' "$t/$w.json"; done | sort -u -t$'\t' -k1,1)
  pp_rm_rf "$t"
  [ "$bad" = 0 ] || echo "warn settings: the check could not build a worker or relay pane's settings in a throwaway worktree, so it cannot tell whether $ml shadows them; run the doctor again from a clean main checkout"
  [ "$n" != 0 ] || [ "$bad" != 0 ] || echo "ok settings: $ml sets no key that a worker or relay pane's own settings write differently"
}
# il_cache_ttl_report -- the doctor's lines on the prompt-cache answers, each "ok <why>" or "warn <what is wrong and the
# fix>". Claude Code applies the main checkout's .claude/settings.local.json over a worktree's own, so a TTL there beats
# the per-worktree answers setup wrote; the relay's own value is the last of: user file, the relay's project and local
# files, the main checkout's local file (the order Claude Code reads them). The owner's key is reported, never edited.
il_cache_ttl_report() {
  local k=CLAUDE_CODE_PROMPT_CACHE_TTL ml=$PP_MAIN/.claude/settings.local.json rw=$PP_WORKSPACES/Chief-of-Staff v n=0 f fs=() s w x mt rt
  mt=$(pp_option promptCacheTtl) rt=$(pp_option relayPromptCacheTtl)
  [ "$mt" = 5m ] || [ "$rt" = 1h ] || { echo "ok prompt cache: setup sets none"; return 0; }
  # A TTL in that file is reported by il_shadow_report; here it only keeps the "no file overrides" line from being said.
  v=$(jq -r --arg k $k '.env[$k] // empty' "$ml" 2>/dev/null)
  [ -z "$v" ] || n=1
  if [ -z "$v" ] && [ "$mt" = 5m ]; then
    # an env key beats the promptCacheTtl keys, so main's answer is the last env key of the user and project files;
    # with none, it is the last promptCacheTtl key of the user, project and local files (the order Claude Code reads them)
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$PP_MAIN/.claude/settings.json"; do [ ! -f "$f" ] || fs+=("$f"); done
    v=$([ ${#fs[@]} = 0 ] || jq -rs --arg k $k 'map(.env[$k] // empty) | last // empty' "${fs[@]}" 2>/dev/null)
    if [ -n "$v" ]; then
      [ "$v" = 5m ] || { n=1; echo "warn prompt cache: main runs $v, not the 5m you chose: an env $k=$v in ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json or $PP_MAIN/.claude/settings.json beats the promptCacheTtl setup wrote; remove that key"; }
    else
      [ ! -f "$ml" ] || fs+=("$ml")
      for s in promptCacheTtl subagentPromptCacheTtl; do
        w=; for f in ${fs[@]+"${fs[@]}"}; do x=$(jq -r --arg s $s '.[$s] // empty' "$f" 2>/dev/null); [ -z "$x" ] || { v=$x w=$f; }; done
        [ -z "$w" ] || [ "$v" = 5m ] || { n=1; echo "warn prompt cache: main runs $v, not the 5m you chose: $s is $v in $w, which is read after the one setup wrote; change it to 5m or remove it"; }
      done
    fi
    fs=()
  fi
  if [ "$rt" = 1h ] && [ -d "$rw" ]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$rw/.claude/settings.json" "$rw/.claude/settings.local.json" "$ml"; do [ ! -f "$f" ] || fs+=("$f"); done
    v=$(jq -rs --arg k $k 'map(.env[$k] // empty) | last // "unset"' "${fs[@]}" 2>/dev/null)
    [ "$v" = 1h ] || { n=1; echo "warn prompt cache: the relay pane runs $v, not the 1h you chose; run setup again, or see the line above"; }
  fi
  [ "$n" != 0 ] || echo "ok prompt cache: no file overrides the answers setup wrote"
}
# il_options_report -- the doctor's line for each /config option (issue 245): the value its readers take, and where it
# comes from: /config, the project's file (the dashboard's: this machine's), or the default.
il_options_report() {
  local k s
  for k in $(jq -r '.userConfig | keys_unsorted[]' "$IL_ROOT/.claude-plugin/plugin.json"); do
    s=$(pp_option "$k" source); [ "$s" != default ] || s="the default"
    echo "ok option $k: $(pp_option "$k" | sed 's/^$/none/') (from $s)"
  done
}
# il_plugin_options <user settings> <answers> [<given answers>] -- setup's answers into /config's options (issue 245),
# under the key the plugin is enabled by: <answers> (carried over from the project's file) each only where /config has
# none, and the owner's /config answer that differs is named; <given answers>, this run's own (issue 312), over the
# key's value, as the owner gave them now. What it adds where there was none is recorded in the machine's manifest, by
# file and key, for il_plugin_options_out: a value it replaced was the owner's, and uninstall leaves the key.
il_plugin_options() {
  local add doc g=${3:-'{}'}
  # No file yet is an empty one: a role key (issue 312) has no home but this file.
  doc=$(il_read "$1") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  [ "$(jq -c --argjson g "$g" '. + $g' <<<"$2")" != '{}' ] || return 0
  # A "project" picker answer is none (issue 293): setup's answer replaces it.
  jq -r --argjson a "$2" --argjson g "$g" "$PP_OPTS_KEY"' (.pluginConfigs[key].options // {}) as $o | $a | to_entries[] | .key as $k | select(($g | has($k) | not) and $o[.key] != null and $o[.key] != "project" and $o[.key] != .value)
    | "note: \(.key) is \($o[.key]) in /config, which beats this answer (\(.value)); change it with /config"' <<<"$doc"
  [ -z "${IL_PLAN:-}" ] || { echo "plan: would add this setup's answers to /config's options where it has none, and this run's --option answers over theirs ($1)"; return 0; }
  add=$(jq -c --argjson a "$2" --argjson g "$g" "$PP_OPTS_KEY"' key as $p | (.pluginConfigs[$p].options // {}) as $o | {($p): ($a + $g | with_entries(select($o[.key] == null or $o[.key] == "project")))}' <<<"$doc") || return 1
  # Recorded before it is written: update's rollback deletes a recorded file with no prior as one setup made.
  il_record "$IL_MACHINE" merge "$1" || return 1
  doc=$(jq --argjson a "$2" --argjson g "$g" "$PP_OPTS_KEY"' key as $p | .pluginConfigs[$p].options = ($a + (.pluginConfigs[$p].options // {} | with_entries(select(.value != "project"))) + $g)' <<<"$doc") \
    && il_write "$1" <<<"$doc" || return 1
  il_set "$IL_MACHINE" --arg f "$1" --argjson n "$add" '.entries[$f].options = ((.entries[$f].options // {}) * $n)'
}
# il_main_model <manifest> <settings file> [off] -- main's model and effort: the orchestratorModel and
# orchestratorEffort keys, as that file's model and effortLevel. The value each replaced is kept (mainModelWas). An
# unset key writes nothing, and a value setup wrote earlier that nobody changed since goes back to the kept one; off
# (uninstall) puts back every such value.
il_main_model() {
  local m=$1 f=$2 doc r s='{}' w
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  r=$(jq -c --arg p "$f" '.entries[$p] | {set: (.mainModel // {}), was: (.mainModelWas // {})}' "$m" 2>/dev/null) || r='{"set":{},"was":{}}'
  [ "${3:-}" = off ] || s=$(jq -cn --arg mo "$(pp_role_option orchestrator model 2>/dev/null)" --arg ef "$(pp_role_option orchestrator effort 2>/dev/null)" \
    '{model: $mo, effortLevel: $ef} | with_entries(select(.value != ""))')
  [ "$(jq -c .set <<<"$r")$s" != '{}{}' ] || return 0
  # Back to the kept value where setup's still stands; then each value s replaces is the one now kept.
  w=$(jq -c --argjson r "$r" --argjson s "$s" '. as $d | reduce ($r.set | to_entries[] | select($d[.key] == .value) | .key) as $k
    (.; if $r.was | has($k) then .[$k] = $r.was[$k] else del(.[$k]) end)
    | {doc: (. + $s), was: (. as $b | $s | with_entries(.value = $b[.key]) | with_entries(select(.value != null)))}' <<<"$doc") \
    && jq .doc <<<"$w" | il_write "$f" \
    && il_set "$m" --arg p "$f" --argjson s "$s" --argjson w "$(jq -c .was <<<"$w")" \
      'if $s == {} then del(.entries[$p].mainModel, .entries[$p].mainModelWas) else .entries[$p].mainModel = $s | .entries[$p].mainModelWas = $w end'
}
# il_profile_files <manifest> -- every Claude Code user settings file setup wrote to, one a line, by the manifest:
# CLAUDE_CONFIG_DIR today may not be the profile it was then.
il_profile_files() { [ ! -s "$1" ] || jq -r '.entries | keys[] | select(endswith("/settings.json"))' "$1"; }
# il_status_was <manifest> <user settings> -- the status line in that file now, before setup sets its own. The first
# one setup replaces in each profile's file is the owner's; a second answer must not take the first for it.
il_status_was() {
  local d w
  ! jq -e --arg p "$2" '.entries[$p] | has("statusLine")' "$1" >/dev/null 2>&1 || return 0
  d=$(il_read "$2") || return 1; w=$(jq -c '.statusLine // null' <<<"$d" 2>/dev/null) || w=
  il_set "$1" --arg p "$2" --argjson was "${w:-null}" '.entries[$p].statusLine = {was: $was}'
}
# il_status_set <manifest> <user settings> <command> -- setup's status line into the file, and recorded as set.
il_status_set() {
  local st
  st=$(il_read "$2") || return 1; [ -n "${st//[[:space:]]/}" ] || st='{}'
  st=$(jq --arg c "$3" '.statusLine = {type: "command", command: $c}' <<<"$st") && il_write "$2" <<<"$st" \
    && il_set "$1" --arg p "$2" --argjson set "$(jq -c .statusLine <<<"$st")" '.entries[$p].statusLine.set = $set'
}
# il_status_out <manifest> <user settings> -- the status line setup set goes back to the one before it; one the owner
# set since is the owner's. A manifest from before status lines were kept per file has one top-level record: today's
# profile's, as that setup read it.
il_status_out() {
  local sl j
  sl=$(jq -c --arg p "$2" --arg s "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" \
    '.entries[$p].statusLine // (if $p == $s then .statusLine else null end) | select(.set) // empty' "$1" 2>/dev/null)
  [ -n "$sl" ] && [ -e "$2" ] || return 0
  if [ "$(jq -c '.statusLine' "$2")" = "$(jq -c .set <<<"$sl")" ]; then
    j=$(jq --argjson was "$(jq -c .was <<<"$sl")" 'if $was == null then del(.statusLine) else .statusLine = $was end' "$2") && il_write "$2" <<<"$j"
  else echo "the status line changed since setup, left as it is: $2"; fi
}
# il_profiles_out <manifest> -- the plugin's parts out of every profile's settings file setup wrote to: the auto-mode
# lines, the permission rules, /config's pre-filled options and the status line.
il_profiles_out() {
  local f
  while IFS= read -r f; do
    [ ! -e "$f" ] || { il_auto_mode "$1" "$f" remove && il_allow_set "$1" "$f" '[]' && il_plugin_options_out "$1" "$f" && il_status_out "$1" "$f"; } || return 1
  done < <(il_profile_files "$1")
}
# il_plugin_options_out <manifest> <user settings> -- the options il_plugin_options added out again, each only while it
# still holds the value setup wrote: one the owner changed in /config since is the owner's.
il_plugin_options_out() {
  local rec doc
  rec=$(jq -c --arg f "$2" '.entries[$f].options // empty' "$1" 2>/dev/null); [ -n "$rec" ] || return 0
  doc=$(il_read "$2") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  doc=$(jq --argjson r "$rec" 'reduce ($r | to_entries[]) as $k (.;
      reduce ($k.value | to_entries[]) as $o (.; if .pluginConfigs[$k.key].options[$o.key] == $o.value then del(.pluginConfigs[$k.key].options[$o.key]) else . end)
      | if .pluginConfigs[$k.key].options == {} then del(.pluginConfigs[$k.key].options) else . end
      | if .pluginConfigs[$k.key] == {} then del(.pluginConfigs[$k.key]) else . end)
    | if .pluginConfigs == {} then del(.pluginConfigs) else . end' <<<"$doc") \
    || { echo "commandeck: $2 is not JSON; fix it and run this again" >&2; return 1; }
  il_write "$2" <<<"$doc" && il_set "$1" --arg f "$2" 'del(.entries[$f].options)'
}
# il_tool_search_report -- the doctor's line on MCP tool search, "ok <why>" or "warn <what is wrong>". Whether it is on
# follows Claude Code's docs ("Configure tool search"); each variable is read from the environment, else from `env`
# in the project's local, project and user settings, in that order. The fallbacks by model and by cloud provider
# are not judged: the doctor does not know the session's model.
il_tool_search_report() {
  local want betas url host n why
  tsv() { local x=${!1:-}; [ -n "$x" ] || x=$(jq -r --arg k "$1" '.env[$k] // empty' "$PP_MAIN/.claude/settings.local.json" "$PP_MAIN/.claude/settings.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null | head -1); printf '%s' "$x"; }
  want=$(tsv ENABLE_TOOL_SEARCH) betas=$(tsv CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS) url=$(tsv ANTHROPIC_BASE_URL)
  host=${url#*://}; host=${host%%[/:]*}
  if [ -n "$betas" ]; then why="CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS is set"
  elif [ "$want" = false ]; then why="ENABLE_TOOL_SEARCH=false"
  elif [ -z "$want" ] && [ -n "$host" ] && [ "$host" != api.anthropic.com ]; then why="ANTHROPIC_BASE_URL is $host, not api.anthropic.com, and ENABLE_TOOL_SEARCH is unset; ENABLE_TOOL_SEARCH=true turns it on"
  fi
  n=$( { jq -r --arg p "$PP_MAIN" '(.mcpServers // {}, .projects[$p].mcpServers // {}) | keys[]' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"; jq -r '(.mcpServers // {}) | keys[]' "$PP_MAIN/.mcp.json"; } 2>/dev/null | sort -u | wc -l | tr -d ' ')
  if [ -n "${why:-}" ]; then echo "warn tool search: tool search is off ($why), so every tool of $n MCP servers loads on every turn"
  else echo "ok tool search: on, so $n MCP servers add their tool names to a turn, not every tool"; fi
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
  # No file yet is an empty object, read as one: a plan has nothing on disk to read back.
  j=$(il_read "$f") || return 1; [ -n "${j//[[:space:]]/}" ] || { [ -n "$1" ] || return 0; j='{}'; }
  if [ -n "$1" ]; then
    j=$(jq --arg m "$IL_OURS_RE" --arg r "$(il_shq "$1")" --slurpfile t "$IL_ROOT/templates/codex-hooks.json" '
        def ours: (.command // "") | test($m);
        ($t[0].hooks | walk(if type == "string" then gsub("__PLUGIN_ROOT__"; $r) else . end)) as $th
        | .hooks = reduce ($th | keys_unsorted[]) as $e (.hooks // {};
            if any(.[$e][]?.hooks[]?; ours)
            then .[$e] |= map(.hooks |= map(if ours then . + $th[$e][0].hooks[0] else . end))
            else .[$e] = (.[$e] // []) + $th[$e] end)' <<<"$j")
  else
    j=$(jq --arg m "$IL_OURS_RE" '
        .hooks |= with_entries(.value |= map(.hooks |= map(select((.command // "") | test($m) | not)) | select(.hooks != [])) | select(.value != []))
        | if .hooks == {} then del(.hooks) else . end' <<<"$j")
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
# il_notify_argv -- Codex's notify command, one word a line; nothing when it has none. Read with tomllib.
il_notify_argv() {
  python3 -c 'import sys, tomllib
try: n = tomllib.load(open(sys.argv[1], "rb")).get("notify")
except (OSError, ValueError): n = None
if isinstance(n, list): print("\n".join(str(w) for w in n))' "$IL_CODEX/config.toml" 2>/dev/null
}
# il_notify_wrapper -- the owner's script notify runs (Codex takes one command, so
# a second tool needs a wrapper calling both): its last word that is a file, not
# the plugin's hook itself. Nothing when notify is the hook or names no file.
il_notify_wrapper() {
  local w f=
  while IFS= read -r w; do [ ! -f "$w" ] || f=$w; done < <(il_notify_argv)
  case $f in ''|*/hooks/codex-notify.sh) ;; *) printf '%s\n' "$f" ;; esac
}
# il_notify_hooks <file> -- each plugin hook path a wrapper names outside a
# comment, one a line, a quoted path whole (it may hold a space). The wrapper is
# read as text, never run: a line its own code never reaches still counts.
il_notify_hooks() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null | sed 's/[[:space:]]#.*//' | grep -oE "\"[^\"]*/hooks/codex-notify\.sh\"|'[^']*/hooks/codex-notify\.sh'|[^\"' =]*/hooks/codex-notify\.sh" \
    | sed "s/^[\"']//; s/[\"']\$//" | sort -u
}
# il_notify_stale <file> -- the hook paths in it that are not this plugin's current hook.
il_notify_stale() {
  local p
  while IFS= read -r p; do
    [ "$(readlink -f "${p/#\~/$HOME}" 2>/dev/null)" = "$(readlink -f "$IL_ROOT/hooks/codex-notify.sh")" ] || printf '%s\n' "$p"
  done < <(il_notify_hooks "$1")
}
# il_notify_report -- the doctor's line on Codex's one notify command: "ok <why>"
# when it calls this plugin's hook, straight or through the owner's wrapper,
# else "warn <what is wrong and the fix>".
il_notify_report() {
  local hook=$IL_ROOT/hooks/codex-notify.sh w stale up lost="so a finished Codex turn waits for the orchestrator's next check"
  up="bash $(printf '%q' "$PP_SCRIPTS")/update.sh"
  w=$(il_notify_wrapper)
  if [ -z "$(il_notify_argv)" ]; then echo "warn codex notify: $IL_CODEX/config.toml has no notify line, $lost; run: $up, or add above its first table: $(il_notify_line "$IL_LINK")"
  elif grep -qxF -- "$(il_notify_line "$IL_ROOT")" "$IL_CODEX/config.toml"; then echo "ok codex notify: the line calls this plugin's hook"
  elif [ -z "$w" ]; then echo "warn codex notify: $IL_CODEX/config.toml runs $(il_notify_argv | paste -sd' ' -), not this plugin's hook $hook, $lost; run: $up"
  elif [ -z "$(il_notify_hooks "$w")" ]; then echo "warn codex notify: the wrapper $w does not call the plugin's hook, $lost; add this line to it: \"$IL_LINK/hooks/codex-notify.sh\" \"\$@\""
  elif stale=$(il_notify_stale "$w"); [ -n "$stale" ]; then echo "warn codex notify: the wrapper $w calls an older plugin's hook ($(paste -sd' ' - <<<"$stale")), not this one's $hook; run: $up, which points it at $IL_LINK/hooks/codex-notify.sh"
  else echo "ok codex notify: through the wrapper $w, which names this plugin's hook outside a comment (read as text, not run)"; fi
}
# il_notify_repoint <manifest> [yes|no] -- a wrapper that calls an older plugin's
# hook is the owner's file: with no answer this prints the question (the old line
# and the new), on no what the doctor will warn, and only on yes does it call the
# stable link instead (IL_LINK, re-pointed at every setup and update), so no
# update leaves it on an old version again. Only those exact paths change.
il_notify_repoint() {
  local w s t p old new
  w=$(il_notify_wrapper); [ -n "$w" ] || return 0
  # A path that is the stable link is not asked about: setup re-points the link in this same run (issue 207).
  s=$(il_notify_stale "$w" | while IFS= read -r p; do [ "${p/#\~/$HOME}" = "$IL_LINK/hooks/codex-notify.sh" ] || printf '%s\n' "$p"; done)
  [ -n "$s" ] || return 0
  t=$(cat "$w") old=$(grep -F -f <(printf '%s\n' "$s") "$w" | paste -sd'|' - | sed 's/|/ \/ /g')
  new=$old
  while IFS= read -r p; do t=${t//"$p"/"$IL_LINK/hooks/codex-notify.sh"} new=${new//"$p"/"$IL_LINK/hooks/codex-notify.sh"}; done <<<"$s"
  [ "$new" != "$old" ] || return 0
  case ${2:-} in
    yes) il_record "$1" merge "$w" && printf '%s\n' "$t" | il_write "$w" \
           && echo "codex notify: $w now calls $IL_LINK/hooks/codex-notify.sh, not $(paste -sd' ' - <<<"$s")" ;;
    no) echo "codex notify: the wrapper $w was left as it is; the doctor will warn: $(il_notify_report | sed 's/^warn //')" ;;
    *) echo "codex notify: ASK: the wrapper $w calls an older plugin's hook. Old line: $old New line: $new Change it: --notify-wrapper yes; leave it: --notify-wrapper no" ;;
  esac
}
il_notify() {
  local f=$IL_CODEX/config.toml rest cur
  cur=$(il_read "$f") || return 1
  rest=$(grep -vE '^notify = \[".*/hooks/codex-notify\.sh"\]$' <<<"$cur" || true)
  [ -z "$1" ] || grep -qE '^[[:space:]]*notify[[:space:]]*=' <<<"$rest" || rest=$(il_notify_line "$1")${rest:+$'\n'$rest}
  [ "$rest" = "$cur" ] || printf '%s\n' "$rest" | il_write "$f"
}

# il_block <file> [text file] -- the plugin's marked block in an instruction
# file: replaced by <text file>'s content, or taken out when none is given.
il_block() {
  local new
  [ -n "${2:-}" ] || [ -e "$1" ] || return 0
  new=$(il_block_text "$1" "${2:-}") || return 1; [ -e "$1" ] && [ "$new" = "$(il_cat "$1")" ] || printf '%s\n' "$new" | il_write "$1"
}
# il_block_text <file> [text file] -- the file's text with that block replaced where it stands (or taken out), the
# owner's text as it was. A file without the block gets it at the end. In place, as Ansible's blockinfile: replacing
# by removal and append moved each block below the other and left a blank line on every run (issue 208).
il_block_text() {
  local body='' cur
  cur=$(il_read "$1") || return 1
  if [ -n "${2:-}" ] && grep -qxF -- "$IL_BEGIN" <<<"$cur"; then
    IL_TEXT=$2 awk -v b="$IL_BEGIN" -v e="$IL_END" '$0 == b && !done { print; while ((getline l < ENVIRON["IL_TEXT"]) > 0) print l; print e; done = 1 }
      $0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' <<<"$cur"
    return
  fi
  body=$(awk -v b="$IL_BEGIN" -v e="$IL_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' <<<"$cur")
  if [ -n "${2:-}" ]; then { [ -z "$body" ] || printf '%s\n\n' "$body"; printf '%s\n' "$IL_BEGIN"; cat "$2"; printf '%s\n' "$IL_END"; }
  else printf '%s\n' "$body"; fi
}
# il_put <manifest> <file> <text> -- an owner's file becomes <text>, with a backup first; the same text writes nothing.
il_put() {
  [ ! -e "$2" ] || [ "$3" != "$(il_cat "$2")" ] || return 0
  il_backup "$1" "$2" && printf '%s\n' "$3" | il_write "$2"
}

# il_global <install|block|merge|skip|''> <tag> <template> <flag> -- the template as the
# plugin's own marked block in IL_GLOBAL. install writes it only into a file
# setup itself created; block adds it to the owner's file, or replaces the one
# an earlier run added; merge does the same with only the rules the owner's file
# does not already have (merge-rules.py: exact matches); skip and no answer leave
# the file as it is. The owner's own text is never changed, and a copy of the file
# is kept beside it before the first change of the day (il_backup). Run after
# IL_GLOBAL is recorded in the machine manifest, which says whether setup made it.
il_global() {
  local body
  case $1 in
    # The same check in a plan: one writes nothing, so a file the run itself would create is still not on disk.
    install) [ ! -e "$IL_GLOBAL" ] || [ "$(jq -r --arg p "$IL_GLOBAL" '.entries[$p].prior // empty' "$IL_MACHINE" 2>/dev/null)" = "did not exist" ] \
      || { echo "global $2: $IL_GLOBAL exists, left as it is; to add it as a marked block: $4 block, or only what it lacks: $4 merge"; return 0; }
      body=$(cat "$3") ;;
    block) body=$(cat "$3") ;;
    merge) body=$(python3 "$IL_ROOT/scripts/merge-rules.py" "$3" --against "$IL_GLOBAL") || return 1
      [ -z "${IL_PLAN:-}" ] || python3 "$IL_ROOT/scripts/merge-rules.py" "$3" --against "$IL_GLOBAL" --report | sed "s/^/plan: global $2: /" ;;
    *) return 0 ;;
  esac
  il_put "$IL_MACHINE" "$IL_GLOBAL" "$(IL_BEGIN="<!-- commandeck:$2:begin -->" IL_END="<!-- commandeck:$2:end -->" il_block_text "$IL_GLOBAL" <(printf '%s\n' "$body"))"
}

# il_backup <manifest> <file> -- a copy of an owner's file, <file>.commandeck-bak-<date>, made before setup
# first changes it that day, beside it where the owner sees it. Recorded as kind "backup": uninstall
# removes it once the file is back to the bytes it copies, and keeps it otherwise. An existing one is kept.
il_backup() {
  local b=$2.commandeck-bak-$(date +%Y%m%d)
  # A file setup itself created holds nothing of the owner's to keep.
  [ -s "$2" ] && [ ! -e "$b" ] && [ "$(jq -r --arg p "$2" '.entries[$p].prior // empty' "$1" 2>/dev/null)" != "did not exist" ] || return 0
  # A plan says it once per file: the copy is taken once, before the first change.
  if [ -n "${IL_PLAN:-}" ]; then
    case $'\n'${IL_BAK_SAID:-} in *$'\n'"$2"$'\n'*) return 0 ;; esac; IL_BAK_SAID+=$2$'\n'
    echo "plan: would copy $2 to $b first (a backup; yours to keep)"; return 0
  fi
  il_record "$1" backup "$b" && cp -p "$2" "$b" && { [ -z "${IL_WROTE:-}" ] || printf 'backup\t%s\n' "$b" >> "$IL_WROTE"; }
}

# il_rules_against -- the project's own rule files main loads, as merge-rules.py arguments: CLAUDE.md and
# .claude/rules/*.md, and the settings' excludes (claudeMdExcludes), which merge-rules.py matches as Claude Code
# does. A path-scoped rules file loads only for its paths: merge-rules.py counts it for nothing.
il_rules_against() {
  local f
  for f in "$PP_MAIN/.claude/settings.json" "$PP_MAIN/.claude/settings.local.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    jq -r '.claudeMdExcludes[]? | strings | "--exclude", .' "$f" 2>/dev/null || true; done
  for f in "$PP_MAIN/CLAUDE.md" "$PP_MAIN"/.claude/rules/*.md; do [ ! -f "$f" ] || printf -- '--against\n%s\n' "$f"; done
}
# il_own <manifest> <owner's file> <plugin template> <replace|merge|skip|''> [--drop|--keep <id>]... -- the owner's
# own AGENT_STARTUP.md or .claude/main-session.md, which the session hook loads instead of the plugin's.
# replace changes no file: the answer, saved in the config (ownFiles), has the hook load the plugin's
# version; merge adds, in a marked block, the plugin's rules it lacks (merge-rules.py: exact matches
# against it; --drop and --keep are the owner's answers by rule id); skip, or no answer, leaves it
# as it is. A merge into main-session.md goes ahead of the owner's "## Details (not injected)" heading, which
# ends what the hook loads, and only the part above it counts as the owner's. The block is committed and each
# seat's settings may exclude other project rules, so the session hook, not setup, leaves out of it what the
# project's CLAUDE.md and .claude/rules/ state for the seat it starts (the plan says so).
il_own() {
  local m=$1 f=$2 t=$3 c=$4 a=() body rest n
  shift 4
  [ -f "$f" ] || return 0
  # A merge block an earlier run added comes out on any other answer.
  [ "$c" = merge ] || ! il_cat "$f" | grep -qxF '<!-- commandeck:merge:begin -->' \
    || il_put "$m" "$f" "$(IL_BEGIN='<!-- commandeck:merge:begin -->' IL_END='<!-- commandeck:merge:end -->' il_block_text "$f")"
  case $c in
    merge) il_record "$m" merge "$f"
      # main-session.md's first line is its persona and its Details stay on disk: neither is a rule to add.
      if [ "${f##*/}" = main-session.md ]; then body=$(tail -n +2 "$t" | awk '/^## Details \(not injected\)/ {exit} 1')
      else body=$(cat "$t"); fi
      a=("$@")
      [ -z "${IL_PLAN:-}" ] || python3 "$IL_ROOT/scripts/merge-rules.py" - --against "$f" ${a[@]+"${a[@]}"} --report <<<"$body" | sed "s|^|plan: $f: |"
      # The block keeps the plugin's own scripts/... paths: the file is committed, and the session hook
      # writes this machine's plugin folder into the block as it loads it.
      body=$(python3 "$IL_ROOT/scripts/merge-rules.py" - --against "$f" ${a[@]+"${a[@]}"} <<<"$body") || return 1
      [ -z "${IL_PLAN:-}" ] || echo "plan: $f: main's sessions also drop any plugin rule your rule files already state."
      rest=$(il_read "$f" | awk -v b="<!-- commandeck:merge:begin -->" -v e="<!-- commandeck:merge:end -->" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }') || return 1
      n=$(grep -n -m1 '^## Details (not injected)' <<<"$rest" | cut -d: -f1) || n=
      if [ -n "$n" ]; then
        il_put "$m" "$f" "$(head -n $((n - 1)) <<<"$rest"; printf '%s\n%s\n\n%s\n' "<!-- commandeck:merge:begin -->" "$body" "<!-- commandeck:merge:end -->"; tail -n +"$n" <<<"$rest")"
      else
        il_put "$m" "$f" "$(IL_BEGIN="<!-- commandeck:merge:begin -->" IL_END="<!-- commandeck:merge:end -->" il_block_text "$f" <(printf '%s\n' "$body"))"
      fi ;;
  esac
}
# il_global_out -- both blocks out of IL_GLOBAL; the owner's text stays.
il_global_out() {
  local t
  for t in claude-md rules; do IL_BEGIN="<!-- commandeck:$t:begin -->" IL_END="<!-- commandeck:$t:end -->" il_block "$IL_GLOBAL"; done
}

# il_lines <manifest> <file> [line...] -- the plugin's own lines in a line-list
# file (git's exclude list) become exactly these, each added once at the end.
il_lines() {
  local m=$1 f=$2 old l body
  shift 2
  old=$( { cat "$m" 2>/dev/null || echo '{}'; } | jq -r --arg p "$f" '.entries[$p].added // [] | .[]') || return 1
  body=$(il_read "$f") || return 1
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
    if [ "$kind" = backup ]; then
      # Last (sorted so): the file it copies is back by now, or was left as the owner changed it.
      if cmp -s "$p" "${p%.commandeck-bak-*}"; then rm -f "$p"
      elif [ -e "$p" ]; then echo "kept setup's copy of ${p%.commandeck-bak-*} as it was before setup: $p"; fi
    elif [ "$prior" = "dangling link" ]; then
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
  done < <(jq -r '.entries | to_entries | sort_by(.value.kind == "backup")[] | select(.value.prior and .value.kind != "dir") | [.value.kind, .value.prior, .key] | @tsv' "$m")
  # The folders setup made, deepest first; one that now holds something stays.
  jq -r '.entries | to_entries[] | select(.value.kind == "dir") | .key' "$m" | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- \
    | while IFS= read -r p; do rmdir "$p" 2>/dev/null || true; done
  rm -f "$m"
}

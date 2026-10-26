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
IL_NOUPDATE='check_for_update_on_startup = false # commandeck: no update prompt in launched panes'   # issue 314: the one line setup adds to the Codex config, uninstall takes out
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
IL_STATE=('*.commandeck-bak-*' .claude/settings.local.json .claude/main-session.settings.json .claude/builder-events.jsonl .claude/metrics/decisions.jsonl .claude/metrics/seat-events.jsonl
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
# the file become exactly <rules>, less the ones revoked there (scripts/revoke.sh); the ones it added before are in
# the manifest, revoked ones included.
il_allow_set() {
  local m=$1 f=$2 new=$3 old rv j added doc
  # No file, or an empty one, is an empty object: jq prints nothing for no input.
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  old=$( { cat "$m" 2>/dev/null || echo '{}'; } | jq -c --arg p "$f" '.entries[$p].added // []') || return 1
  rv=$( { cat "$m" 2>/dev/null || echo '{}'; } | jq -c --arg p "$f" '.entries[$p].revoked.added // []') || return 1
  jq -r --argjson rv "$rv" '.[] | select(IN($rv[]))' <<<"$new" | while IFS= read -r j; do il_choice_note "rule $j"; done
  # Only what the owner did not already have is the plugin's to take back out.
  added=$(jq -c --argjson old "$old" --argjson new "$new" '$new - ((.permissions.allow // []) - $old)' <<<"$doc" 2>/dev/null) || added=$new
  j=$(jq --argjson old "$old" --argjson new "$new" --argjson rv "$rv" '
      ((.permissions.allow // []) - $old) as $rest
      | .permissions.allow = $rest + ($new - $rest - $rv)
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
# il_cache_ttl <manifest> <settings file> <5m|1h|off> -- the subagents' prompt-cache lifetime (issue 367), the
# Builder and worker answer; the main conversation's and each pane's own TTL go elsewhere (il_main_lean, worktree-setup.sh).
# A key the owner set is left as it is; a value setup itself wrote earlier is replaced; off takes out only a value
# setup wrote and nobody changed since (an older setup's promptCacheTtl too).
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
    s=$(jq -c '{subagentPromptCacheTtl: $t} | with_entries(select(.key as $k | ($d | has($k) | not) or $d[$k] == $r[$k]))' --arg t "$3" --argjson d "$doc" --argjson r "$r" -n)
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
  local m=$1 f=$2 doc new how rec stale
  case $3 in
    leave) return 0 ;;
    add)
      doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
      new=$(jq -cn --arg h "$(jq -r '.homepage // empty' "$IL_ROOT/.claude-plugin/plugin.json")" --arg l "$IL_LINK" '[
        "Trusted repo: \($h) (the Commandeck workflow plugin). Its scripts and hooks under \($l) are this workflow'"'"'s own tools, run by every pane.",
        "Key internal services: Orca panes on this machine. The relay pane (the worktree ending in /Chief-of-Staff) passes the owner'"'"'s answers to main word for word; main checks each against the owner'"'"'s ruling log before acting; while auto-decide is on it also sends its own decisions, titled auto-decided, which main checks against the decisions ledger instead."]')
      how=$(jq -r '(.autoMode.environment // null) as $e | if $e == null then "new" elif ($e | type) == "array" and any($e[]; . == "$defaults") then "append" else "refuse" end' <<<"$doc" 2>/dev/null) \
        || { echo "commandeck: $f is not JSON; fix it and run this again" >&2; return 1; }
      if [ "$how" = refuse ]; then
        echo "auto mode: the environment list in $f has no \"\$defaults\", so it replaces Claude Code's built-in list; left as it is. To keep the built-in rules and add this plugin's lines, add \"\$defaults\" to the list and run setup again"
        return 0
      fi
      # A line the owner revoked (scripts/revoke.sh) stays out.
      rec=$(il_profile_record "$m" "$f"); [ -n "$rec" ] || rec='{"revoked": {}}'
      jq -r --argjson r "$rec" '.[] | select(IN($r.revoked.autoMode // [] | .[]))' <<<"$new" | while IFS= read -r l; do il_choice_note "auto-mode $l"; done
      # A line recorded by an earlier version and no longer in the set (the relay line, reworded) is replaced, not kept beside the new one.
      stale=$(jq -c --argjson o "$(jq -c --arg p "$f" '.entries[$p].autoMode.added // []' "$m" 2>/dev/null || echo '[]')" '$o - .' <<<"$new")
      new=$(jq -c --argjson d "$doc" --argjson r "$rec" '$d.autoMode.environment as $e | . - ($e // []) - ($r.revoked.autoMode // [])' <<<"$new")
      [ "$new" != '[]' ] || [ "$stale" != '[]' ] || return 0
      il_record "$m" merge "$f" || return 1
      doc=$(jq --argjson n "$new" --argjson x "$stale" --argjson r "$rec" "$IL_CHOICES"'.autoMode.environment = ((.autoMode.environment // ["$defaults"]) - $x + $n) | choices($r)' <<<"$doc") && il_write "$f" <<<"$doc" \
        && il_set "$m" --arg p "$f" --argjson n "$new" --argjson x "$stale" --arg how "$how" '.entries[$p].autoMode = {created: ((.entries[$p].autoMode.created // false) or $how == "new"), added: (((.entries[$p].autoMode.added // []) - $x) + $n)}' ;;
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
# il_cache_ttl_report -- the doctor's lines on the prompt-cache answers (issue 367), one per role, each "ok <why>" or
# "warn <what is wrong and the fix>". Main's TTL lives in the file only a main started with --settings reads, so no
# user or project file changes it (a --settings file beats them); a worker pane's is its worktree's local file, and
# Claude Code applies the main checkout's .claude/settings.local.json over it (il_shadow_report names that file); the
# relay's own value is the last of: user file, the relay's project and local files, the main checkout's local file
# (the order Claude Code reads them). The owner's key is reported, never edited.
il_cache_ttl_report() {
  local k=CLAUDE_CODE_PROMPT_CACHE_TTL ml=$PP_MAIN/.claude/settings.local.json rw=$PP_WORKSPACES/Chief-of-Staff v n f fs=() x mt wt rt
  mt=$(pp_option mainPromptCacheTtl) wt=$(pp_option workerPromptCacheTtl) rt=$(pp_option relayPromptCacheTtl)
  case $mt in
    5m|1h)
      f=$PP_MAIN/$IL_MAIN_LEAN_FILE
      v=$(jq -r --arg k $k '.env[$k] // empty' "$f" 2>/dev/null)
      if [ "$v" = "$mt" ]; then echo "ok prompt cache: main $mt (.claude/main-session.settings.json; read only by a main started with claude --settings $f)"
      else echo "warn prompt cache: main's $f holds ${v:-no} $k, not the $mt you chose; run setup again, or, if the key is yours, change or remove it"; fi ;;
    leave) echo "ok prompt cache: main leave (setup sets none)" ;;
    *) echo "ok prompt cache: main not answered (setup sets none; /commandeck:setup asks)" ;;
  esac
  case $wt in
    5m|1h)
      n=0
      for f in "$PP_WORKSPACES"/*/.claude/settings.local.json "$ml"; do
        [ -f "$f" ] || continue
        case $f in "$rw"/*) continue ;; esac
        x=$(jq -r --arg k $k '.env[$k] // empty' "$f" 2>/dev/null)
        [ -z "$x" ] || [ "$x" = "$wt" ] || { n=1; echo "warn prompt cache: workers run $x, not the $wt you chose: $k is $x in $f; change it to $wt or remove it"; }
      done
      # subagents: the last subagentPromptCacheTtl of the project and local files (the order Claude Code reads them)
      for f in "$PP_MAIN/.claude/settings.json" "$ml"; do
        [ -f "$f" ] || continue
        x=$(jq -r '.subagentPromptCacheTtl // empty' "$f" 2>/dev/null)
        [ -z "$x" ] || [ "$x" = "$wt" ] || { n=1; echo "warn prompt cache: subagents run $x, not the $wt you chose: subagentPromptCacheTtl is $x in $f; change it to $wt or remove it"; }
      done
      [ "$n" != 0 ] || echo "ok prompt cache: workers $wt (each worktree's .claude/settings.local.json; subagents: subagentPromptCacheTtl in .claude/settings.json)" ;;
    leave) echo "ok prompt cache: workers leave (setup sets none)" ;;
    *) echo "ok prompt cache: workers not answered (setup sets none; /commandeck:setup asks)" ;;
  esac
  case $rt in
    5m|1h)
      if [ -d "$rw" ]; then
        for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$rw/.claude/settings.json" "$rw/.claude/settings.local.json" "$ml"; do [ ! -f "$f" ] || fs+=("$f"); done
        v=$(jq -rs --arg k $k 'map(.env[$k] // empty) | last // "unset"' "${fs[@]}" 2>/dev/null)
      else v=$rt; fi
      if [ "$v" = "$rt" ]; then echo "ok prompt cache: relay $rt (the relay worktree's .claude/settings.local.json)"
      else echo "warn prompt cache: the relay pane runs $v, not the $rt you chose; run setup again, or see the line above"; fi ;;
    leave) echo "ok prompt cache: relay leave (setup sets none)" ;;
  esac
}
# il_options_report -- the doctor's line for each /config option (issue 245): the value its readers take, and where it
# comes from: /config, the project's file (the dashboard's: this machine's), or the default.
il_options_report() {
  local k s v
  for k in $(jq -r '.userConfig | keys_unsorted[]' "$IL_ROOT/.claude-plugin/plugin.json"); do
    IFS=$'\t' read -r s v < <(pp_option "$k" both); [ "$s" != default ] || s="the default"
    echo "ok option $k: ${v:-none} (from $s)"
  done
}
# il_plugin_options <user settings> <answers> [<given answers>] -- setup's answers into /config's options (issue 245),
# under the key the plugin is enabled by: <answers> (carried over from the project's file) each only where /config has
# none, and the owner's /config answer that differs is named; <given answers>, this run's own (issue 312), over the
# key's value, as the owner gave them now. What it adds where there was none is recorded in the machine's manifest, by
# file and key, for il_plugin_options_out: a value it replaced was the owner's, and uninstall leaves the key.
il_plugin_options() {
  local add want doc g=${3:-'{}'} a=$2 rec rv k
  # No file yet is an empty one: a role key (issue 312) has no home but this file.
  doc=$(il_read "$1") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  # An option the owner chose with revoke.sh is left out, this run's own answer too: only revoke.sh writes or clears
  # that list.
  rec=$(il_profile_record "$IL_MACHINE" "$1"); [ -n "$rec" ] || rec='{"revoked": {}}'
  rv=$(jq -c --argjson r "$rec" "$PP_OPTS_KEY"' key as $p | {p: $p, k: ($r.revoked.options[$p] // {} | keys)}' <<<"$doc") || return 1
  while IFS= read -r k; do il_choice_note "option $(jq -r .p <<<"$rv") $k"; done \
    < <(jq -r --argjson rv "$rv" --argjson g "$g" '. + $g | keys[] | select(IN($rv.k[]))' <<<"$a")
  a=$(jq -c --argjson rv "$rv" 'with_entries(select(.key | IN($rv.k[]) | not))' <<<"$a") \
    && g=$(jq -c --argjson rv "$rv" 'with_entries(select(.key | IN($rv.k[]) | not))' <<<"$g") || return 1
  set -- "$1" "$a" "$g"
  [ "$(jq -c --argjson g "$g" '. + $g' <<<"$2")" != '{}' ] || return 0
  # A "project" picker answer is none (issue 293): setup's answer replaces it.
  jq -r --argjson a "$2" --argjson g "$g" "$PP_OPTS_KEY"' (.pluginConfigs[key].options // {}) as $o | $a | to_entries[] | .key as $k | select(($g | has($k) | not) and $o[.key] != null and $o[.key] != "project" and $o[.key] != .value)
    | "note: \(.key) is \($o[.key]) in /config, which beats this answer (\(.value)); change it with /config"' <<<"$doc"
  [ -z "${IL_PLAN:-}" ] || { echo "plan: would add this setup's answers to /config's options where it has none, and this run's --option answers over theirs ($1)"; return 0; }
  add=$(jq -c --argjson a "$2" --argjson g "$g" "$PP_OPTS_KEY"' key as $p | (.pluginConfigs[$p].options // {}) as $o | {($p): ($a + $g | with_entries(select($o[.key] == null or $o[.key] == "project")))}' <<<"$doc") || return 1
  # optionsWant: every value setup writes, those added and this run's own answers over the owner's. The profile
  # repair (il_profile_repair) puts them back; `options` stays what uninstall takes out.
  want=$(jq -c --argjson add "$add" --argjson g "$g" "$PP_OPTS_KEY"' key as $p | {($p): (($add[$p] // {}) + $g)}' <<<"$doc") || return 1
  # Recorded before it is written: update's rollback deletes a recorded file with no prior as one setup made.
  il_record "$IL_MACHINE" merge "$1" || return 1
  doc=$(jq --argjson a "$2" --argjson g "$g" --argjson r "$rec" "$PP_OPTS_KEY$IL_CHOICES"' key as $p | .pluginConfigs[$p].options = ($a + (.pluginConfigs[$p].options // {} | with_entries(select(.value != "project"))) + $g) | choices($r)' <<<"$doc") \
    && il_write "$1" <<<"$doc" || return 1
  il_set "$IL_MACHINE" --arg f "$1" --argjson n "$add" --argjson w "$want" \
    '.entries[$f].options = ((.entries[$f].options // {}) * $n) | .entries[$f].optionsWant = ((.entries[$f].optionsWant // {}) * $w)'
}
# il_main_model <manifest> <settings file> [off] -- main's model and effort: the orchestratorModel and
# orchestratorEffort keys, as that file's model and effortLevel. The value each replaced is kept (mainModelWas). An
# unset effort key writes routing's orchestrator effort (medium), an unset model key nothing, and a value setup wrote
# earlier that nobody changed since goes back to the kept one; off (uninstall) puts back every such value.
il_main_model() {
  local m=$1 f=$2 doc r s='{}' w
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  r=$(jq -c --arg p "$f" '.entries[$p] | {set: (.mainModel // {}), was: (.mainModelWas // {})}' "$m" 2>/dev/null) || r='{"set":{},"was":{}}'
  [ "${3:-}" = off ] || s=$(jq -cn --arg mo "$(pp_role_option orchestrator model 2>/dev/null)" \
    --arg ef "$(pp_route_json orchestrator 2>/dev/null | jq -r '.effort // empty')" \
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
# IL_MAIN_LEAN -- what main's session turns off to keep its start lean: the add-on plugins main never uses
# (config/addons.tsv). Written into IL_MAIN_LEAN_FILE, which only a
# session started with `claude --settings <it>` reads. Never into main's settings.local.json: Claude Code applies that
# file over every worktree session's own (docs: settings, "Where Claude Code keeps the local file in a git
# repository"), so a cut there reaches every worker and the relay.
IL_MAIN_LEAN_FILE=.claude/main-session.settings.json
IL_MAIN_LEAN='{"enabledPlugins": {"ui-themes@ui-themes": false, "mattpocock-skills@claude-plugins-official": false}}'
# il_main_lean <manifest> <settings file> [off|5m|1h|leave] -- IL_MAIN_LEAN written into that file, key by key, and
# with main's prompt-cache answer (issue 367) its env CLAUDE_CODE_PROMPT_CACHE_TTL: only a main started with
# claude --settings <this file> reads it. A key the owner already holds, with any value, stays and is named (nothing
# is replaced, so nothing is kept but what setup added: mainLean in the manifest). A rerun keeps its own keys; off
# (uninstall) takes out those still holding setup's value. leave writes no TTL, and keeps the one setup wrote while
# the file still holds it (with its record, so uninstall takes it out).
il_main_lean() {
  local m=$1 f=$2 doc r w want=$IL_MAIN_LEAN k=CLAUDE_CODE_PROMPT_CACHE_TTL t=${3:-leave}
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  r=$(jq -c --arg p "$f" '.entries[$p].mainLean // {}' "$m" 2>/dev/null) || r='{}'
  case $t in
    off) want='{}' ;;
    5m|1h) ;;
    *) t=$(jq -r --arg k $k --argjson d "$doc" '.env[$k] as $v | select($v != null and $v == $d.env[$k]) | $v' <<<"$r") ;;
  esac
  [ -z "$t" ] || [ "$t" = off ] || want=$(jq -c --arg k $k --arg t "$t" '.env[$k] = $t' <<<"$want")
  [ "$r$want" != '{}{}' ] || return 0
  w=$(jq -c --argjson r "$r" --argjson want "$want" 'def leaves: [paths(type != "object")];
    . as $d | ($r | leaves | map(select(. as $p | ($d | getpath($p)) == ($r | getpath($p))))) as $mine
    | ($want | leaves) as $wp
    | ($wp | map(select(. as $p | (($d | getpath($p)) == null) or ($p | IN($mine[]))))) as $take
    | (delpaths($mine - $take) | reduce ($mine | map(.[0]) | unique[]) as $k (.; if .[$k] == {} then del(.[$k]) else . end)) as $base
    | {doc: (reduce $take[] as $p ($base; setpath($p; $want | getpath($p)))),
       set: (reduce $take[] as $p ({}; setpath($p; $want | getpath($p)))),
       skip: (($wp - $take) | map(join(".")))}' <<<"$doc") || return 1
  jq -r '.skip[] | "note: \(.) is already set in main'"'"'s settings, which beats setup'"'"'s lean list; left as it is"' <<<"$w"
  jq .doc <<<"$w" | il_write "$f" \
    && il_set "$m" --arg p "$f" --argjson s "$(jq -c .set <<<"$w")" \
      'if $s == {} then del(.entries[$p].mainLean) else .entries[$p].mainLean = $s end'
}
# il_profile_files <manifest> -- every Claude Code user settings file setup wrote to, one a line, by the manifest:
# CLAUDE_CONFIG_DIR today may not be the profile it was then.
il_profile_files() { [ ! -s "$1" ] || jq -r '.entries | keys[] | select(endswith("/settings.json"))' "$1"; }
# il_profile_lock [<wait s>] -- the one lock of every read-modify-write of a profile settings file setup recorded and of
# the manifests: the launch repair, revoke.sh, and setup's and uninstall's writes. Every pane on a profile shares its
# file and the machine's manifest, so a write from a stale read undoes another pane's change. Held on the manifests'
# folder, not a lock file, so no lock state can go missing while a manifest is there; held to the end of the process.
# Taken once per process: a second flock on a new open would wait on itself. No folder (nothing installed) is no lock.
il_profile_lock() {
  [ -z "${IL_PROFILE_LOCK_FD:-}" ] || return 0
  [ -d "$IL_DIR" ] && exec {IL_PROFILE_LOCK_FD}<"$IL_DIR" || return 1
  flock -w "${1:-30}" "$IL_PROFILE_LOCK_FD" || { exec {IL_PROFILE_LOCK_FD}<&-; IL_PROFILE_LOCK_FD=; echo "commandeck: $IL_DIR stayed locked for ${1:-30} s" >&2; return 1; }
}
# il_profile_record <manifest> <profile settings file> -- the manifest's record of what setup put in that file, one
# line of JSON, or nothing. A manifest from before optionsWant has the options in `options`, and one from before status
# lines were kept per file its status line at the top (il_status_out).
il_profile_record() {
  # No manifest yet (a first setup --plan writes none) is no record, not a jq error set -e turns into a silent exit.
  [ -e "$1" ] || return 0
  jq -c --arg p "$2" --arg s "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" '.statusLine as $top | .entries[$p] // empty
    | .statusLine //= (if $p == $s then $top else null end) | .optionsWant = ((.options // {}) * (.optionsWant // {}))
    | .revoked //= {}' "$1" 2>/dev/null
}
# IL_CHOICES -- jq's choices($r): the owner's choices made with scripts/revoke.sh ($r.revoked, $r il_profile_record's
# line) applied to a settings doc. The one rule of every writer of the four kinds: il_auto_mode add, il_plugin_options,
# il_status_set, il_profile_repair and revoke.sh (il_allow_set leaves a revoked rule out through `added`). A revoked
# rule or auto-mode line comes out. A removed status line or option comes out where it holds setup's value, the status
# line back to the one before setup's; a value of the owner's own stays. A kept value is written. Setup's value is the
# one revoke.sh saved with the choice, else the record's, so the take-out needs no other part of the record.
IL_CHOICES='def choices($r): ($r.revoked // {}) as $rv
  | (if ((try .permissions.allow catch null) | type) == "array" then .permissions.allow -= ($rv.added // []) else . end)
  | (if ((try .autoMode.environment catch null) | type) == "array" then .autoMode.environment -= ($rv.autoMode // []) else . end)
  | (if $rv | has("statusLine") | not then .
     elif $rv.statusLine.keep != null then .statusLine = $rv.statusLine.keep
     else .statusLine as $c | ($rv.statusLine | if has("was") then .was else $r.statusLine.was end) as $w
       | if $c != null and $c != $w and any($rv.statusLine.set, $r.statusLine.set; . == $c)
         then (if $w == null then del(.statusLine) else .statusLine = $w end) else . end end)
  | reduce (($rv.options // {}) | to_entries[] | .key as $p | .value | to_entries[] | {p: $p, k: .key, c: .value}) as $o (.;
      (try .pluginConfigs[$o.p].options[$o.k] catch null) as $v
      | if $o.c.keep != null then .pluginConfigs[$o.p].options[$o.k] = $o.c.keep
        elif $v != null and any($o.c.set, $r.optionsWant[$o.p][$o.k]; . == $v) then del(.pluginConfigs[$o.p].options[$o.k])
        else . end);'
# il_choice_note <what> -- setup's line for a value it left out because the owner chose it with revoke.sh; <what> is
# the value as revoke.sh names it.
il_choice_note() { echo "$1: chosen with /commandeck:revoke, so setup left its own value out; /commandeck:revoke undo $1 brings it back at the next launch"; }
# il_profile_repair <manifest> <profile settings file> -- Orca copies ~/.claude/settings.json over a profile's file at a
# launch, and with it goes what setup put there: the status line (statusLine.set), /config's options (optionsWant), the
# auto-mode lines (autoMode.added) and the permission rules (added). Run at a launch, this puts each back where the
# file lacks it or holds another value. The owner's choices (`revoked`, written only by scripts/revoke.sh) win: a rule
# or auto-mode line there is not put back; a status line or option there is the owner's kept value ({keep: <value>})
# or none ({keep: null}). The copy can hold setup's values (the home file is setup's too), so each of those is taken
# out of it by choices (IL_CHOICES), as revoke.sh takes it out. It never reads a removal from the file, so a hand edit
# of these is undone at the next launch. The first record (the undo point) is not touched, so uninstall removes exactly what it did. Writes nothing,
# and stamps nothing, when nothing changed. The read, the write and the stamp hold il_profile_lock; one that cannot
# take it writes nothing, and the next launch repairs.
il_profile_repair() {
  local m=$1 f=$2 rec doc out
  [ -d "$IL_DIR" ] || return 0
  il_profile_lock 30 || return 1
  rec=$(il_profile_record "$m" "$f"); [ -n "$rec" ] || return 0
  doc=$(il_read "$f") || return 1; [ -n "${doc//[[:space:]]/}" ] || doc='{}'
  # Setup's values the owner did not choose otherwise go back, then the owner's choices; the stamp names what changed.
  out=$(jq -c --argjson r "$rec" "$IL_CHOICES"'
    def arr: if type == "array" then . else [] end;
    . as $d | (try .autoMode.environment catch null) as $e | (try .permissions.allow catch null) as $al | $r.revoked as $rv
    | (if ($rv | has("statusLine") | not) and $r.statusLine.set != null then .statusLine = $r.statusLine.set else . end)
    | reduce ($r.optionsWant | to_entries[] | .key as $p | .value | to_entries[] | .key as $k
        | select(($rv.options[$p] // {}) | has($k) | not) | {p: $p, k: $k, v: .value}) as $o (.;
        if (try .pluginConfigs[$o.p].options[$o.k] catch null) != $o.v then .pluginConfigs[$o.p].options[$o.k] = $o.v else . end)
    | (($r.autoMode.added // []) - ($rv.autoMode // []) - ($e | arr)) as $a
    | if $a != [] and ($e == null or (($e | type) == "array" and any($e[]; . == "$defaults")))
      then .autoMode.environment = (($e // ["$defaults"]) + $a) else . end
    | (($r.added // []) - ($rv.added // []) - ($al | arr)) as $pa
    | if $pa != [] and ($al == null or ($al | type) == "array") then .permissions.allow = (($al // []) + $pa) else . end
    | choices($r) | . as $n
    | {doc: $n, keys: [[["statusLine", "statusLine"], ["options", "pluginConfigs"], ["autoMode", "autoMode"], ["permissions", "permissions"]][]
        | select($d[.[1]] != $n[.[1]]) | .[0]]}' <<<"$doc" 2>/dev/null) \
    || { echo "commandeck: $f is not JSON; left as it is" >&2; return 1; }
  [ "$(jq '.keys | length' <<<"$out")" != 0 ] || return 0
  jq .doc <<<"$out" | il_write "$f" \
    && il_set "$m" --arg p "$f" --arg at "$(date -u +%FT%TZ)" --argjson k "$(jq -c .keys <<<"$out")" '.entries[$p].repaired = {at: $at, keys: $k}'
}
# il_profile_repair_report -- the doctor's lines on profile files an Orca launch overwrote, and on the owner's choices
# made in them with scripts/revoke.sh, "ok <what happened>".
il_profile_repair_report() {
  jq -r '.entries | to_entries[]
    | (select(.value.repaired) | "ok profile settings: \(.key) was overwritten at a launch and repaired at \(.value.repaired.at) (\(.value.repaired.keys | join(", "))); a hand edit of setup'"'"'s status line, options, auto-mode lines or permission rules is undone at the next launch: remove one, or keep your own value, with /commandeck:revoke"),
      (select((.value.revoked // {}) != {}) | .key as $f | .value.revoked as $v | [($v.added // [])[],
        (($v.autoMode // []) | length | select(. > 0) | "\(.) auto-mode line\(if . > 1 then "s" else "" end)"),
        ($v.statusLine // empty | "the status line \(if .keep == null then "(removed)" else "(kept: your own)" end)"),
        ($v.options // {} | to_entries[] | .key as $p | .value | to_entries[] | "option \($p) \(.key) \(if .value.keep == null then "(removed)" else "(kept: \(.value.keep | tojson))" end)")]
        | select(length > 0) | "ok profile settings: \($f): chosen with /commandeck:revoke, a launch does not put setup'"'"'s value back: \(join(", "))")' "$IL_MACHINE" 2>/dev/null || true
}
# il_rules_audit_line <project> -- setup's closing warning: the rules audit's finding count in that project, nothing when there is none.
# The audit exits 1 on a finding and 2 and up when it did not run; neither stops setup, which runs under set -e.
il_rules_audit_line() {
  local out rc=0 s="see bash $(printf '%q' "$IL_ROOT/scripts")/rules-audit.sh"
  out=$(python3 "$IL_ROOT/scripts/instruction-lint.py" --repo "$1" 2>/dev/null) || rc=$?
  case $rc in
    0) ;;
    1) echo "rules audit: $(grep -c . <<<"$out") findings (a warning; $s)" ;;
    *) echo "rules audit: did not run (exit $rc; $s)" ;;
  esac
}
# il_status_was <manifest> <user settings> -- the status line in that file now, before setup sets its own. The first
# one setup replaces in each profile's file is the owner's; a second answer must not take the first for it.
il_status_was() {
  local d w
  ! jq -e --arg p "$2" '.entries[$p] | has("statusLine")' "$1" >/dev/null 2>&1 || return 0
  d=$(il_read "$2") || return 1; w=$(jq -c '.statusLine // null' <<<"$d" 2>/dev/null) || w=
  il_set "$1" --arg p "$2" --argjson was "${w:-null}" '.entries[$p].statusLine = {was: $was}'
}
# il_status_set <manifest> <user settings> <command> -- setup's status line into the file, and recorded as set. One the
# owner chose with revoke.sh is left as the choice has it.
il_status_set() {
  local st rec set
  st=$(il_read "$2") || return 1; [ -n "${st//[[:space:]]/}" ] || st='{}'
  rec=$(il_profile_record "$1" "$2"); [ -n "$rec" ] || rec='{"revoked": {}}'
  set=$(jq -cn --arg c "$3" '{type: "command", command: $c}')
  ! jq -e '.revoked | has("statusLine")' <<<"$rec" >/dev/null || il_choice_note status-line
  st=$(jq --argjson s "$set" --argjson r "$rec" "$IL_CHOICES"'(if $r.revoked | has("statusLine") then . else .statusLine = $s end) | choices($r)' <<<"$st") \
    && il_write "$2" <<<"$st" && il_set "$1" --arg p "$2" --argjson set "$set" '.entries[$p].statusLine.set = $set'
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
# il_codex_trust_report -- the doctor's line on Codex's hook trust (issue 315): "ok <why>" when every hook in the Codex
# home is trusted, else "bad <the hooks not trusted or modified and the fix>". It checks every entry, not only the
# plugin's: any one of them opens each Codex pane on the review menu.
il_codex_trust_report() {
  local err fix
  if err=$(python3 "$PP_SCRIPTS/codex-hook-trust.py" --check --all "$IL_CODEX" 2>&1); then
    echo "ok codex trust: every hook in $IL_CODEX is trusted"; return 0
  fi
  if [ "$(pp_option trustAllHooks)" = true ]; then fix="each Codex launch trusts them again; to do it now run: python3 $(printf '%q' "$PP_SCRIPTS")/codex-hook-trust.py --all"
  else fix="turn on trust-all so each launch trusts them again (setup.sh --trust-all-hooks on), or review them with /hooks in a Codex pane"; fi
  echo "bad codex trust: $(grep -c . <<<"$err") hook(s) in $IL_CODEX would open each Codex pane on the review menu: $(printf '%s\n' "${err//"$IL_CODEX: "/}" | awk 'NR > 1 { printf "; " } { printf "%s", $0 }'). $fix"
}
# il_codex_update [plan] -- issue 314: Codex is updated here, outside any pane, never left on an old version that opens
# its panes on the update prompt. Prints one `codex:` line (nothing when there is no codex); status 0 latest or updated,
# 1 the update FAILED, 2 the installed or latest version is unknown. Codex's own `codex update` knows which installer
# the user used. `plan` names the update and runs nothing. The update ends at TERM after 300 s and KILL 10 s later; its
# output goes to a file, so a child that outlives the kill cannot hold a pipe open. Updated means a version read after
# it, newer than before; a failure names the version read then, or why none was.
il_codex_update() {
  local i l n j o s t why now
  command -v codex >/dev/null 2>&1 || return 0
  i=$(il_codex_version) || { echo "codex: its version is unreadable (codex --version: $i); not updated"; return 2; }
  j=$(curl -fsS --max-time 10 https://api.github.com/repos/openai/codex/releases/latest 2>&1) || true
  l=$(jq -r '.tag_name // empty' <<<"$j" 2>/dev/null) || l=
  l=${l#"${l%%[0-9]*}"}
  n=${j:-no answer}
  [ -n "$l" ] || { echo "codex: $i installed, latest unknown (${n##*$'\n'}); not updated"; return 2; }
  [ "$(printf '%s\n' "$i" "$l" | sort -V | tail -1)" != "$i" ] || { echo "codex: $i, the latest"; return 0; }
  [ "${1:-}" != plan ] || { echo "plan: would update Codex $i -> $l (codex update)"; return 0; }
  o=$(mktemp)
  timeout --kill-after=10 300 codex update </dev/null >"$o" 2>&1 && s=0 || s=$?
  n=$(il_codex_version) && t=0 || t=1
  if [ "$s$t" = 00 ] && [ "$(printf '%s\n' "$i" "$n" | sort -V | tail -1)" != "$i" ]; then rm -f "$o"; echo "codex: updated $i -> $n (codex update)"; return 0; fi
  case $s in 124|137) why="no end in 300 s; stopped" ;; 0) why="it exited 0" ;; *) why=$(grep . "$o" | tail -1); why=${why:-exit $s} ;; esac
  rm -f "$o"
  if [ "$t" = 1 ]; then now="codex --version now: $n"; elif [ "$n" = "$i" ]; then now="Codex stays on $i"; else now="Codex is on $n"; fi
  echo "codex: update $i -> $l FAILED ($why); $now. Run: codex update"; return 1
}
# il_codex_version -- the installed Codex's version, from `codex --version` within 10 s; else why not, status 1.
il_codex_version() {
  local v s
  v=$(timeout --kill-after=2 10 codex --version </dev/null 2>/dev/null) && s=0 || s=$?
  case $s in 0) ;; 124|137) echo "no answer in 10 s"; return 1 ;; *) echo "exit $s"; return 1 ;; esac
  v=$(awk 'NR == 1 { print $NF }' <<<"$v")
  [[ $v =~ ^[0-9]+\.[0-9]+ ]] || { echo "no version in its output"; return 1; }
  echo "$v"
}
# il_codex_update_report -- the doctor's line on Codex's update check: "ok <why>" when check_for_update_on_startup is
# false in the Codex config, else "warn <what is wrong and the fix>". A missing file is the default: on.
il_codex_update_report() {
  local v
  v=$(python3 -c 'import sys, tomllib
try: print(tomllib.load(open(sys.argv[1], "rb")).get("check_for_update_on_startup", True))
except FileNotFoundError: print(True)
except (OSError, ValueError): print("unreadable")' "$IL_CODEX/config.toml" 2>/dev/null)
  case $v in
    False) echo "ok codex update check: off (check_for_update_on_startup = false in $IL_CODEX/config.toml)" ;;
    unreadable) echo "warn codex update check: unknown, $IL_CODEX/config.toml is not readable TOML" ;;
    *) echo "warn codex update check: on in $IL_CODEX/config.toml, so a launched pane can open on Codex's update prompt (the launcher answers Skip); run: bash $(printf '%q' "$PP_SCRIPTS")/update.sh" ;;
  esac
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
# A Codex launch rewrites config.toml holding the folder of the file it resolves to locked (codex-hook-trust.py
# trust_home): this read and write wait for the same lock, and both use the file the link resolved to under it. The
# one retry: the link repointed before the lock or during the write (a refused write included), so the run starts
# over where it points now.
il_notify() {
  local t s
  while t=$(il_codex_config); [ -d "${t%/*}" ]; do
    { flock 9 || return 1; [ "$(il_codex_config)" = "$t" ] || continue; il_notify_set "$1" "$t" && s=0 || s=$?
      [ "$(il_codex_config)" != "$t" ] || return "$s"; } 9<"${t%/*}"
  done
  il_notify_set "$1" "$t"
}
il_codex_config() { readlink -f "$IL_CODEX/config.toml" 2>/dev/null || printf '%s\n' "$IL_CODEX/config.toml"; }
# il_notify_set <root> <file> -- the notify line in <file>, the config.toml il_notify resolved, never the link.
il_notify_set() {
  local f=$2 rest cur seen
  # Taken before the read, so a change during the read also fails the check before the write. LC_ALL=C: GNU stat
  # translates %F, and the check below matches the English word.
  seen=$(LC_ALL=C stat -c '%F %i %.9Y' -- "$f" 2>/dev/null)
  cur=$(il_read "$f") || return 1
  # The plugin's notify and update-check lines come out, then (with a root) each goes back above the first table when the
  # owner has no such key (issue 314). A line is the plugin's only as a root key, read by tomllib: taking it out takes
  # that key out and nothing else, so the same text in an owner's multiline string stays. A file tomllib cannot read
  # loses the lines as text and gets neither back: adding one cannot make it valid.
  rest=$(python3 -c 'import re, sys, tomllib
mark, add = sys.argv[1:]
lines = sys.stdin.read().removesuffix("\n").split("\n")
def load(ls):
    try: return tomllib.loads("\n".join(ls))
    except ValueError: return None
d = load(lines)
for i in reversed(range(len(lines))):
    k = "check_for_update_on_startup" if lines[i] == mark else "notify" if re.fullmatch(r"notify = \[\".*/hooks/codex-notify\.sh\"\]", lines[i]) else None
    if k is None: continue
    t = lines[:i] + lines[i + 1:]
    e = load(t)
    if d is not None and e != {x: v for x, v in d.items() if x != k}: continue
    lines, d = t, e
if add and d is not None:
    if "check_for_update_on_startup" not in d: lines.insert(0, mark)
    if "notify" not in d: lines.insert(0, add)
print("\n".join(lines))' "$IL_NOUPDATE" "${1:+$(il_notify_line "$1")}" <<<"$cur") \
    || { echo "commandeck: $f could not be read with python3's tomllib; nothing was written" >&2; return 1; }
  [ "$rest" != "$cur" ] || return 0
  # Not the regular file read above (a link at either stat, another file, edited): refuse, and il_notify retries a link
  # at its target. Nothing there is a create. A change between this check and il_write's mv is still written over:
  # closing that window needs a lock every other writer honours.
  [ "$(LC_ALL=C stat -c '%F %i %.9Y' -- "$f" 2>/dev/null)" = "$seen" ] && [[ ${seen:-regular} == regular* ]] \
    || { echo "commandeck: $f changed since it was read; nothing was written, run this again" >&2; return 1; }
  printf '%s\n' "$rest" | il_write "$f"
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

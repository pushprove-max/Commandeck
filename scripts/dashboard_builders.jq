# dashboard_builders.jq -- a Builder's card and signals from its event log
#, pure so the tests run it with no collect. Callers: dashboard.sh
# units() and main-watch.sh. Input (jq -s): the log's rows. Args: $now (epoch),
# and optionally sessionAt (epoch the seat's session log was last written, or null).
# Output {lastAt, round, stage, steps, signals}; signals are
# {kind, since (epoch, stable while the condition lasts), limitSec}.
# Limits are owner ruling 2026-10-10: a tool call with no end is
# STUCK past 600 s (test), 180 s (shell), 60 s (tool) -- codex is exempt, its
# pass has its own rows; QUIET is 300 s with nothing open; LOOP is the same
# call three times, or four failed calls, in a row.
def ep: try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch null;
# wait: an inbox wait (`orchestration check --wait`) blocks for 540 s by design.
def limits: {test: 600, shell: 180, tool: 60, wait: 600};
# The newest-first run of equal $f values at the end of the rows; empty for no rows.
def trail(f): reverse | map(f) as $v
  | (first(range(0; length) | select($v[.] != $v[0])) // length) as $n | .[:$n];
map(select(type == "object" and (.event | type) == "string")) as $r
| ($r | map(select(.event == "tool-start"))) as $starts
# A call a guard refused never runs: its tool-refused row (lib/hook-fire-log.sh, every guard) ends it.
# A call denied by a hook that logs no row, or by the auto-mode classifier, has no end row of its own:
# its batch's batch-end row names it. Later calls never end one, since parallel calls can start one after another.
| ($r | map(select(.event == "subagent-stop"))) as $se
# A helper the pane stopped mid-call logs no end for that call: its stop row ends every call it began.
# A running helper's open call, and the pane's own, are ended by their own rows only.
| ($r | map(select(.event == "tool-end" or .event == "search-refused" or .event == "tool-refused"), (select(.event == "batch-end") | .uses[]? | {use: .}),
    (select(.event == "tool-start" and .agent != null and (.agent as $a | any($se[]; .agent_id == $a))) | {use}))) as $ended
| ($r | map(select(.event == "tool-end"))) as $ends
| ($r | map(select(.event == "codex-start"))) as $cs
| ($r | map(select(.event == "codex-end"))) as $ce
| ($r | map(select(.event == "subagent-start"))) as $ss
| ($r | map(select(.event == "subagent-request"))) as $sr
| ([$r[].ts | ep | select(. != null)] | max) as $last
| ([$starts[] | select(.use != null and .kind != "codex" and (.use as $u | any($ended[]; .use == $u) | not))]) as $pending
| ([$starts[] | select(.use == null or (.use as $u | any($ended[]; .use == $u) | not))] | length > 0) as $openTool
# A pass ends at the first codex-end of its pass and round that FOLLOWS it in
# the log: a round run again is open until its own end, whatever the first try left.
| ($r | to_entries) as $ri
| ([$ri[] | select(.value.event == "codex-start") | .key as $i | .value as $c
    | {c: $c, e: (first($ri[] | select(.key > $i and .value.event == "codex-end" and .value.pass == $c.pass and .value.round == $c.round) | .value) // null)}]) as $cx
| ([$cx[] | select(.e == null) | .c]) as $openCodex
| ([$ss[] | select(.agent_id == null or (.agent_id as $a | any($se[]; .agent_id == $a) | not))]) as $openSub
| {
    lastAt: (if $last == null then null else $last | todate end),
    round: ($cs | last | .round // null),
    stage: (if ($openCodex | length) > 0 then "review" elif ($ce | length) > 0 then "fixing" else "building" end),
    steps: (
      [$ss | to_entries[] | .key as $i | .value as $s | ($sr | map(select(.type == $s.type)) | .[
          ($ss[:$i] | map(select(.type == $s.type)) | length)]?) as $q
        | ($se | map(select(.agent_id != null and .agent_id == $s.agent_id)) | first) as $p
        | {kind: "subagent", agentId: $s.agent_id, type: $s.type, modelAsked: (if $q == null then null else $q.model // "" end), model: ($p.model // null),
           tokens: ($p.tokens // null), start: $s.ts, stop: ($p.ts // null), reason: ($p.reason // null)}]
      + [$cx[] | .c as $c | .e as $e
        | {kind: "codex", pass: $c.pass, round: $c.round, start: $c.ts, end: ($e.ts // null), rc: ($e.rc // null)}]
      | sort_by(.start) | reverse),
    signals: (
      # A call that states a longer timeout of its own (a wait on a background test run) is not stuck inside it.
      # Several open calls are one signal, from the earliest: one each gave the same alert twice.
      ([$pending[] | ([limits[.kind] // limits.tool, (.timeoutSec | numbers)] | max) as $lim | (.ts | ep) as $t
        | select($t != null and $now - $t > $lim) | {kind: "stuck", since: $t, limitSec: $lim}]
       | if length > 1 then [min_by(.since)] else . end)
      # One long model turn writes the session log and no event row: quiet is timed from the later of the two.
      + (([$last, ($ARGS.named.sessionAt | numbers)] | max) as $sign
         | if $last != null and $now - $sign > 300 and ($openTool | not) and ($openCodex | length) == 0 and ($openSub | length) == 0
           then [{kind: "quiet", since: $sign, limitSec: 300}] else [] end)
      # Both detectors can see one run (four failures of one call): one episode, from its earliest start.
      + ([([$starts | trail(.call)] | map(select(length >= 3 and .[0].call != null) | .[-1].ts | ep)),
          ([$ends | trail(.ok == false)] | map(select(length >= 4 and .[0].ok == false) | .[-1].ts | ep))]
         | add | map(select(. != null)) | if length == 0 then [] else [{kind: "loop", since: min, limitSec: null}] end)
    )
  }
# The Builds panel's lines: when the log began, the seconds spent inside Codex passes
# (an open pass counted to now) and what is open right now. An empty log measures none of them.
| . + {
    startedAt: ([$r[].ts | select(ep != null)] | first // null),
    reviewSec: (if $last == null then null else [$cs[] | . as $c | (.ts | ep) as $a
        | (($ce | map(select(.pass == $c.pass and .round == $c.round)) | first | .ts // null | if . == null then $now else ep end)) as $b
        | select($a != null and $b != null and $b >= $a) | $b - $a] | add // 0 end),
    waiting: ([($openCodex[] | {kind: "codex", what: .pass, round: .round, since: .ts}),
               ($openSub[] | {kind: "subagent", what: .type, round: null, since: .ts}),
               ($pending[] | {kind: "tool", what: .tool, round: null, since: .ts})] | sort_by(.since))
  }

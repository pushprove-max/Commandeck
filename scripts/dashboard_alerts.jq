# dashboard_alerts.jq -- the Alerts card's rules, pure: dashboard.sh passes
# only what it already collected, so the tests run these rules without a
# collect. Inputs: $parts (the snapshot's top-level parts: projects, host,
# limit), $srcs (the machine's source records), $hasSe/$se (7 days of every
# project's seat-events rows), $preva ([{key: since epoch}] from the last collect, a file: issue 280),
# $now, $s7 (the 7-day window start).
# Output {alerts, since, missing}. An id is <key>-<since epoch>: stable while
# the condition lasts, new once it clears and comes back (the Chief of Staff's
# watcher wakes on any id it has not seen). A project's alert carries the
# project's name in its key and its text: two projects may each have a unit of
# one name. missing names each input not measured now.
def rate: map(.tokens | select(. != null and .input != null and .cachedInput != null))
  | (map(.input) | add // 0) as $i | if $i > 0 then (map(.cachedInput) | add) * 100 / $i else null end;
def r: . * 10 | round | . / 10;
def ts: try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch null;
# Every rule names what to do about it: an alert that needs no action is not raised at all.
def a($key; $sev; $text; $action): {key: $key, severity: $sev, text: "\($text). Action: \($action)"};
# A new Builder writes its whole prompt prefix to cache first, so its early 24 h rate is low by construction.
# Measured on one install, Builders first reached 95% at 2.2M to 3.2M input tokens; the bar starts above that.
def builder_warmup_input: 3300000;

($parts | add // {}) as $d
| ($srcs | add // {}) as $src
| ($d.projects // {} | to_entries) as $projects
| (if $hasSe then $se else null end) as $se
| (if $se == null then null else [$se[] | select((.completedAt // "") >= ($now - 86400 | todate))] end) as $day
| (if $day == null then null else $day | rate end) as $hit
| [
    (if $hit != null and $hit < 95 then a("cache-hit"; "warn"; "Cache hit rate over the last 24 h is \($hit | r)%, under 95%"; "find the seat or role under 95% and the prompt prefix that changed") else empty end),
    # Each role against its own week: reviewers normally run near 90%, so no flat bar.
    ($day // [] | group_by(.role)[] | .[0].role as $role | rate as $r24
      | ([$se[] | select(.role == $role and (.completedAt // "") >= $s7)] | rate) as $r7
      | select($r24 != null and $r7 != null and $r24 <= $r7 - 5)
      | a("cache-role-\($role)"; "warn"; "\($role) cache hit rate over 24 h is \($r24 | r)%, \($r7 - $r24 | r) points under its 7-day \($r7 | r)%"; "read that role's last launches for a changed prefix or a broken reuse")),
    # Used ahead of the week's elapsed share runs out before the reset at this pace.
    # A machine set to API billing paces dollars instead (limit-api below): the two percent alerts stay quiet there.
    # Each follows its own tool's billing: Claude's for Claude (billing), Codex's sign-in for Codex (codexBilling).
    ($d.limit // {} | select(.billing != "api" and .usedPct != null and .goalPct != null and .goalPct > 0 and .usedPct > .goalPct)
      | a("limit-claude"; "crit"; "Claude 7-day limit is on pace to run out before the reset: \(.usedPct | r)% used with \(.goalPct | r)% of the week gone"; "slow dispatch (fewer Builders at once) or move work to Codex")),
    ($d.limit // {} | select(.codexBilling != "api") | .codex // {} | select(.usedPct != null and .goalPct != null and .goalPct > 0 and .usedPct > .goalPct)
      | a("limit-codex"; "crit"; "Codex 7-day limit is on pace to run out before the reset: \(.usedPct | r)% used with \(.goalPct | r)% of the week gone"; "slow dispatch (fewer Builders at once) or move work to Claude")),
    # A machine that pays by API: dollars spent ahead of the weekly limit's even pace. No limit, no alert.
    ($d.limit.api // {} | select(.limitUsd != null and .spentUsd != null and .goalUsd != null and .spentUsd > .goalUsd)
      | a("limit-api"; "crit"; "API spend is on pace to pass the weekly limit before Monday: $\(.spentUsd | round) spent, the even pace for now is $\(.goalUsd | round) of $\(.limitUsd | round)"; "slow dispatch (fewer Builders at once) or move work to the other provider")),
    ($d.limit.cacheWritePct24h // null | select(. != null and . > 5)
      | a("cache-write"; "warn"; "\(. | r)% of input tokens over the last 24 h were written to cache, over 5%"; "find the sessions rewriting cache")),
    # A worker session found an MCP server down within 10 min (pane-budget-gate.sh's stamp, host-wide, in $parts as mcpDown).
    ($d.mcpDown // [] | .[] | select(.server != null and .at != null and $now - .at < 600)
      | a("mcp-down-\(.server)"; "warn"; "\(.server) was not running in a worker session \((($now - .at) / 60) | floor) min ago; workers carry on without it"; "check why the server does not start on this machine; until then workers record it as deferred for main") + {since: .at}),
    ($d.host.swap // {} | select((.totalMb // 0) > 0 and .usedMb != null and .usedMb * 100 > .totalMb * 75)
      | a("host-swap"; "warn"; "Host swap \(.usedMb * 100 / .totalMb | round)% used (\(.usedMb) of \(.totalMb) MB)"; "hold new launches and stop any stray process the awareness hook lists")),
    ($projects[] | .key as $p | .value as $v
      | (($v.guardBlocks // {} | select(.lastHour != null and .perHour != null and .lastHour >= 30 and .lastHour > 3 * .perHour)
          | a("guard-spike-\($p)"; "warn"; "\($p): \(.lastHour) guard blocks in the last hour, over 3 times the \(.perHour | r) an hour average"; "find the pane looping on a refused command and redirect it")),
        # A unit in one stage past 2 h is red on its card; the stage start is the collector's first sighting.
        ($v.units.inFlight // [] | .[] | select(([.stage] | inside(["planning", "building", "review", "fixing", "waiting-main"]))
            and .stageSince != null and ((.stageSince | ts) as $t | $t != null and $now - $t > 7200))
          | a("stage-\($p)/\(.unit)"; "warn"; "\($p): \(.unit) has been in \(.stage) for \(if .stageExact == false then "at least " else "" end)\(($now - (.stageSince | ts)) / 3600 | r) h"; "check the unit: nudge it, re-scope it, or answer what it waits on")
            + {since: (.stageSince | ts)}),
        ($v.needsOwner.decisions // [] | .[] | (.askedAt | ts) as $at | select($at != null and $now - $at > 3600)
          | a("question-\($p)-\(.id)"; "warn"; "\($p): question waiting on \(if .waitsOn == "main" then "main (a Builder's)" else "the owner" end) over 1 h: \(.question)"; "\(if .waitsOn == "main" then "main answers it" else "the owner answers it" end)") + {since: $at}),
        # Issue 295: an answer main never got is the owner's order lost: one the host gave up on, or one failing for 10 min.
        ($v.needsOwner.unsent // [] | .[] | (.firstAt | ts) as $at | select(.state == "gave-up" or ($at != null and $now - $at >= 600))
          | a("answer-\($p)-\(.id)-\(.to)"; "crit"; "\($p): the answer to \(.id) is not sent to \(if .to == "relay" then "the relay" else "main" end)\(if .state == "gave-up" then " and the host gave up" else "" end): \(.reason // .lastError // "no reason recorded")"; "retry it, mark it delivered or drop it on this machine's dashboard")
            + {since: $at}),
        # An open picker blocks the relay pane itself, and its mail waits behind it (main-watch.sh records it, issue 232).
        ($v.chiefOfStaff.picker? // null | select(type == "object" and (.since | type) == "number" and $now - .since >= 1800)
          | a("relay-picker-\($p)"; "warn"; "\($p): relay picker open \(($now - .since) / 60 | floor) min; \(.waiting) messages waiting behind it"; "answer or close the picker in the relay's pane")
            + {since: .since}),
        # A Builder's signals (dashboard_builders.jq), one alert per unit and kind.
        ($v.units.inFlight // [] | .[] | select((.builder.signals | type) == "array") | .unit as $u | .builder.signals[]
          | a("builder-\($p)/\($u)-\(.kind)"; "warn"; "\($p): Builder \($u): \(.kind | ascii_upcase)"; "inspect or nudge the Builder") + {since: .since}),
        # A Builder writes no seat rows: its own session's 24 h usage, summed by the collector.
        ($v.units.inFlight // [] | .[] | .unit as $u | select((.builder.cache24h.input? // 0) >= builder_warmup_input)
          | [.builder.cache24h | {tokens: .}] | rate
          | select(. != null and . < 95) | a("cache-builder-\($p)/\($u)"; "warn"; "\($p): Builder \($u) cache hit rate over the last 24 h is \(. | r)%, under 95%"; "read the Builder's session for a changed prefix or restarts")),
        # Main is meant to restart before it compacts, and a carry the hook could not heal strands its restart (issues 292,
        # 300). Each ends at main's next restart (resumedAt, or restartedAt for a carried checkpoint); a failure under 120 s old is not stranded yet, the restart
        # helper takes seconds. One key per session or checkpoint, so each is told, not folded into the first.
        ($v.mainEvents // {} | (.resumedAt // null | if . == null then null else ts end) as $rs
          | ((.compactions // [])[] | select($rs == null or (.at | ts) > $rs)
              | a("main-compact-\($p)-\(.sid[0:8])"; "crit"; "\($p): main session \(.sid[0:8]) compacted (\(.trigger), \((.preTokens // 0) / 1000 | round)K tokens): main is meant to restart before compaction"; "read the stop hook log for why main did not restart first")
                + {since: (.at | ts)}),
            ((.carryFailed // [])[] | select(($rs == null or (.at | ts) > $rs) and $now - (.at | ts) > 120)
              | a("carry-failed-\($p)-\(.cp | split("/")[-1] | rtrimstr(".md"))"; "crit"; "\($p): main's checkpoint \(.cp | split("/")[-1]) failed the carry-over check and the hook did not carry its items"; "restate the dropped items in the checkpoint, then restart main")
                + {since: (.at | ts)}),
            # The hook carried the items itself (host 48151d13), but main never restarted: its rejected checkpoint stands.
            ((.carried // [])[] | select(.restartedAt == null and $now - (.at | ts) > 120)
              | a("checkpoint-rejected-\($p)-\(.cp | split("/")[-1] | rtrimstr(".md"))"; "crit"; "\($p): main's checkpoint \(.cp | split("/")[-1]) failed the carry-over check: its items were carried automatically but main was not restarted"; "restart main by hand")
                + {since: (.at | ts)})),
        # Collector stale: a project's input serving its last good read.
        ($v.sources // {} | to_entries[] | select(.value.status == "stale")
          | a("stale-\($p)/\(.key)"; "warn"; "\($p): collector input \(.key) is stale: \(.value.error // "its last read failed")"; "fix the collector input named here") + {since: (.value.staleSince | ts)}))
        # Each project's Chief of Staff raises its own: cos-watch-alerts.sh filters on this.
        + {project: $p}),
    ($src | to_entries[] | select(.value.status == "stale")
      | a("stale-\(.key)"; "warn"; "Collector input \(.key) is stale: \(.value.error // "its last read failed")"; "fix the collector input named here") + {since: (.value.staleSince | ts)})
  ]
| ($preva[0] | map_values(if type == "object" then . else {since: .} end)) as $held
| map(. + {since: (.since // $held[.key].since // $now)}) as $act
| {alerts: [$act[] | {id: "\(.key)-\(.since)", severity, text, since: (.since | todate)} + (if .project == null then {} else {project} end)],
   since: (reduce $act[] as $x ({}; .[$x.key] = ($x | {since, severity, text} + (if .project == null then {} else {project} end)))),
   resolved: [$held | to_entries[] | select(.key as $k | all($act[]; .key != $k))
     | {key, since: (.value.since | todate), resolvedAt: ($now | todate), severity: .value.severity, text: .value.text} + (if .value.project == null then {} else {project: .value.project} end)],
   missing: [
     (if $se == null then "seat-events (cache hit rate)" elif $hit == null then "24 h cache hit rate (no measured seat)" else empty end),
     (if $d.limit.billing == "api" then empty elif $d.limit.usedPct == null or $d.limit.goalPct == null then "7-day limit" else empty end),
     (if $d.limit.codexBilling == "api" then empty elif $d.limit.codex.usedPct == null or $d.limit.codex.goalPct == null then "Codex 7-day limit" else empty end),
     (if $d.limit.billing != "api" then empty elif $d.limit.api.spentUsd == null then "API spend"
      elif $d.limit.api.complete != true then "API spend (incomplete)" else empty end),
     (if $d.limit.cacheWritePct24h == null then "24 h cache write share" else empty end),
     (if $d.host.swap == null then "host swap" else empty end),
     (if ($src.projects.status // "") == "not-measured" then "a registered project" else empty end),
     ($projects[] | .key as $p | .value as $v
       | (if $v.guardBlocks.lastHour == null or $v.guardBlocks.perHour == null then "\($p): guard blocks per hour" else empty end),
         (if $v.units.inFlight == null then "\($p): units in flight" else empty end),
         ($v.units.inFlight // [] | .[] | select(.builder != null and (.builder | has("cache24h")) and .builder.cache24h == null) | "\($p): Builder \(.unit) 24 h cache hit rate"),
         (if $v.needsOwner.decisions == null then "\($p): questions for the owner" else empty end),
         (if ($v.sources["builder-logs"].status // "") == "not-measured" then "\($p): Builder event logs" else empty end))
   ]}

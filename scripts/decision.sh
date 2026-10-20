#!/usr/bin/env bash
# decision.sh add <id> <question> <proposedDefault> <source> [--reask <what is new> | --waits-on main] [--options '<a>|<b>[|<c>[|<d>]]']
#           | check <id> <question> [<other question>...] | answer <id> <answer> [--asked-at <askedAt> | --correct]
#           | reopen <id> | list
# The decisions ledger, .claude/metrics/decisions.jsonl in the primary checkout:
# append-only, one complete snapshot per line, the latest line per id wins.
# The dashboard's Needs Owner card shows the unanswered ones with their default;
# the page never adds, answers or applies one. Every read-validate-append holds
# the ledger's lock, so a duplicate id or a double answer cannot race in.
#
# A question the owner still has open, or answered in the last 24 hours, is never put
# to them again: add and check exit 3 naming the earlier decision and its
# answer, and append nothing. Two exceptions (main's ruling): a retry
# after the ruling log voided the owner's last pick of that question as the decoy
# (exit 0, the open row is reused), and --reask with the new facts, logged in
# the source. A --reask of an existing id appends a fresh open snapshot and
# lets that id's picker through once, or, for a chat or earlier day's id, the
# picker whose header names it. Exit 1 is every other failure;
# ask-records-decision.sh blocks the picker on 3 only.
# --waits-on main: a Builder's question to main (orca-wait.sh records it,
# answer-worker.sh answers it). The row carries waitsOn: "main", so the Needs
# Owner card lists it as waiting on main, never as the owner's; it is never a
# repeat of an owner's question, only of its own id.
# Test seams: paths.sh's COMMANDECK_MAIN; COMMANDECK_RULING_LOG.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
. "$(dirname "$0")/paths.sh" || exit 1
L=$PP_MAIN/.claude/metrics/decisions.jsonl
. "$(dirname "$0")/../hooks/lib/project.sh" && pp_project "$PP_MAIN"
RULINGS=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
die() { echo "decision: $*" >&2; exit 1; }
usage() { die "usage: decision.sh add <id> <question> <proposedDefault> <source> [--reask <what is new> | --waits-on main] [--options '<a>|<b>[|<c>[|<d>]]'] | check <id> <question> [<other question>...] | answer <id> <answer> [--asked-at <askedAt> | --correct] | reopen <id> | list"; }

# lock <-s|-x> -- held on the ledger itself until the script exits.
lock() { [ -r "$L" ] && exec 9<"$L" || die "no ledger at $L"; flock "$1" 9 || die "could not lock $L"; }

# The latest snapshot per id, in asking order. One malformed line fails the
# whole read: a corrupt ledger is never an empty one.
fold() {
  jq -cs 'if all(.[]; type == "object"
                 and (keys - ["history", "waitsOn", "options"] == ["answer","answeredAt","askedAt","id","proposedDefault","question","source"])
                 and (.id | type == "string" and length > 0))
          then [to_entries[] | .value + {_i: .key}] | group_by(.id) | map(last + {_i: first._i}) | sort_by(._i) | map(del(._i))
          else error("malformed record") end' "$L" 2>/dev/null || die "malformed ledger $L"
}

append() { printf '%s\n' "$1" >> "$L" || die "could not append to $L"; printf '%s\n' "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# fresh <askedAt> -- now, for a new snapshot of an id last asked at <askedAt>
# (empty for a new id). askedAt is how the watcher's seen mark and answer
# --asked-at tell snapshots apart, and stamps are whole seconds, so a tie waits
# for the next second; a stamp ahead of the clock would hide the ask from a
# prompt that answers it now.
fresh() { local t; t=$(now); [ "$t" != "$1" ] || { sleep 1; t=$(now); }; printf '%s\n' "$t"; }

# Same question: equal once case, punctuation and spacing are dropped, or a
# reworded one whose content words (stop words out, plural/-ing/-ed endings
# off) are at least half, and at least three, already in the earlier question,
# naming no other environment and no other number or ordinal ("round 13",
# "fourteenth round": each round is its own decision). "thirteenth",
# "13th" and "13" are one number; cardinal words ("one more round") are not
# numbers. Measured on the 2026-10-03/04 repeats: 0.57,
# 0.57 and 0.78 matched; the changed reader order scored 0.36 and stays a new
# decision. A ceiling: a paraphrase sharing under
# half its words gets through; a new decision reusing most of an open one's
# words is refused and goes through --reask.
SAME_Q='
def stop: ["a","an","the","to","of","in","on","at","for","by","with","and","or","but","so","if","it","its",
  "is","are","be","been","was","were","do","does","did","should","shall","would","could","can","will","may",
  "must","we","i","you","they","them","their","this","that","these","those","there","here","what","which",
  "who","how","when","where","why","now","then","than","as","from","into","up","out","any","all","some","new",
  "happen","going","forward","instead","get","keep","yes","no","not","just","also","only","our","my","your",
  "about","s","t","plus"];
def stem: if length > 5 and endswith("ing") then .[:-3] elif length > 4 and endswith("ed") then .[:-2]
  elif length > 3 and endswith("s") and (endswith("ss") | not) then .[:-1] else . end;
def flat: ascii_downcase | [scan("[a-z0-9]+")] | join(" ");
def toks: ascii_downcase | gsub("can[’'"'"']?t\\b"; "cannot") | gsub("[’'"'"']"; "") | [scan("[a-z0-9]+")];
def words: toks | map(select(. as $w | stop | index($w) | not) | stem) | unique;
def envs: ascii_downcase | [scan("[a-z0-9]+")] | map(select(IN("dev", "prod", "production", "staging")) | if . == "production" then "prod" else . end) | unique;
def nums: ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
  "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
  "nineteenth", "twentieth"] as $ord
  | toks | map(if test("^[0-9]+(st|nd|rd|th)?$") then sub("(st|nd|rd|th)$"; "") | tonumber
    else . as $w | $ord | index($w) // empty | . + 1 end) | unique;
def recent: .answeredAt == null or .answeredAt >= (now - 86400 | strftime("%Y-%m-%dT%H:%M:%SZ"));
def same_q($new): . as $old | ($new | flat) == ($old | flat) or (
  ($new | words) as $n | ($old | words) as $o | ([$n[] | select(. as $w | $o | index($w))] | length) as $k
  | $k >= 3 and $k * 2 >= ($n | length)
    and (($new | envs) as $a | ($old | envs) as $b | $a == $b or $a == [] or $b == [])
    and (($new | nums) as $a | ($old | nums) as $b | $a == $b or $a == [] or $b == []));'

# dup <cur> <id> <question> -- the newest earlier decision this question
# repeats, or nothing: still open, or answered in the last 24 hours. Only when
# none does is the same id asking something else a write failure (exit 1).
dup() {
  local d
  d=$(jq -c --arg q "$3" "$SAME_Q"'[.[] | select(.waitsOn == null and recent and (.question | same_q($q)))] | last // empty' <<<"$1")
  [ -n "$d" ] && { printf '%s\n' "$d"; return; }
  ! jq -e --arg id "$2" 'any(.[]; .id == $id)' <<<"$1" >/dev/null || die "decision $2 already exists"
}

# decoy <snapshot> -- 0 when the ruling log's latest ask of this very question,
# in this checkout, since it was asked, is the voided decoy pick. A
# missing log grants nothing; an unreadable one refuses rather than guess.
decoy() {
  jq -e '.answeredAt == null' <<<"$1" >/dev/null || return 1
  [ -e "$RULINGS" ] || return 1
  local r
  r=$(jq -s --argjson d "$1" --arg main "$PP_MAIN" '
      [.[] | select(.source == "ask" and .question == $d.question and (.utc // "") >= $d.askedAt
                    and ((.cwd // "") == $main or ((.cwd // "") | startswith($main + "/"))))]
      | sort_by(.utc) | last | .void == true' "$RULINGS" 2>/dev/null) \
    || refuse "$1" "and the ruling log $RULINGS is unreadable, so a decoy retry cannot be confirmed"
  [ "$r" = true ]
}

# refuse <snapshot> [note] -- exit 3: the question is already the owner's, with their answer.
refuse() {
  jq -r --arg note "${2:-}" '"decision: this repeats \(.id), asked \(.askedAt): "
    + (if .answeredAt == null then "still open, no answer yet" else "answered \"\(.answer)\" at \(.answeredAt)" end)
    + ". Use that decision; re-ask only with new facts (decision.sh add ... --reask \"<what is new>\")."
    + (if $note == "" then "" else " " + $note end)' <<<"$1" >&2
  printf '%s\n' "$1"
  exit 3
}

# gate <cur> <id> <question> [<source>] -- refuse a repeat unless it is a decoy
# retry or the one picker an explicit --reask of this id armed: either prints
# the open snapshot and exits 0. With <source> (add), the re-ask's grant is
# spent: one snapshot keeps its id, exact question, default and askedAt under
# the caller's source, so the same picker again is a repeat. A retry must keep
# the original header and day: ruling-log.sh closes the row by that id.
gate() {
  local d
  d=$(jq -c --arg id "$2" --arg q "$3" "$SAME_Q"'.[] | select(.id == $id and .answeredAt == null
      and (.question | same_q($q)))' <<<"$1")
  if [ -n "$d" ] && jq -e '(.source // "") | contains("; re-ask: ")' <<<"$d" >/dev/null; then
    [ $# -lt 4 ] || { append "$(jq -c --arg s "$4" '.source = $s' <<<"$d")"; exit 0; }
    printf '%s\n' "$d"; exit 0
  fi
  # Before the repeat match: a decoy retry reuses its own open row, whatever
  # other decision it resembles.
  [ -n "$d" ] && decoy "$d" && { printf '%s\n' "$d"; exit 0; }
  # A re-asked chat decision, or an earlier day's, has an id no picker gets
  # today: the grant passes the picker whose header names it (same id once the
  # -YYYY-MM-DD day is off both), and the add closes the old row and moves it
  # to the picker's id, the one ruling-log.sh answers.
  d=$(jq -c --arg id "$2" --arg q "$3" "$SAME_Q"'def slug: sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; "");
      [.[] | select(.answeredAt == null and .id != $id and (.id | slug) == ($id | slug)
        and ((.source // "") | contains("; re-ask: ")) and (.question | same_q($q)))] | last // empty' <<<"$1")
  if [ -n "$d" ]; then
    [ $# -lt 4 ] || { append "$(jq -c --arg a "re-asked as $2" --arg at "$(now)" '.answeredAt = $at | .answer = $a' <<<"$d")" >/dev/null
      append "$(jq -c --arg id "$2" --arg s "$4" '.id = $id | .source = $s' <<<"$d")"; exit 0; }
    printf '%s\n' "$d"; exit 0
  fi
  d=$(dup "$1" "$2" "$3") || exit 1
  [ -n "$d" ] || return 0
  [ "$(jq -r .id <<<"$d")" != "$2" ] || refuse "$d"
  refuse "$d" "A retry after a voided decoy pick keeps that decision's original header, the same day."
}

case "${1:-}" in
  add)
    reask="" waits="" opts=""
    # --options: the 2 to 4 answers the picker offered (issue 240), the dashboard's buttons; last on the line.
    if [ $# -ge 7 ] && [ "${*: -2:1}" = --options ]; then
      opts=$(jq -cne --arg o "${*: -1}" '$o | split("|") | select(length >= 2 and length <= 4 and all(length > 0))') \
        || die "--options takes 2 to 4 answers, none empty, split by |"
      set -- "${@:1:$#-2}"
    fi
    if [ $# -eq 7 ] && [ "$6" = --reask ]; then
      reask=$7; [ -n "${reask//[[:space:]]/}" ] || die "--reask needs the new facts"
    elif [ $# -eq 7 ] && [ "$6" = --waits-on ]; then
      [ "$7" = main ] || die "--waits-on takes main"; waits=$7
    else
      [ $# -eq 5 ] || usage
    fi
    [ -n "$2" ] || die "an id is required"
    # The first ask on a fresh checkout starts the ledger; answer and list still refuse a missing one.
    [ -e "$L" ] || { mkdir -p "${L%/*}" && : >> "$L"; } || die "could not create $L"
    lock -x
    cur=$(fold) || exit 1
    if [ -n "$waits" ]; then
      ! jq -e --arg id "$2" 'any(.[]; .id == $id)' <<<"$cur" >/dev/null || die "decision $2 already exists"
    elif [ -z "$reask" ]; then gate "$cur" "$2" "$3" "$5"; fi
    append "$(jq -cn --arg id "$2" --arg q "$3" --arg d "$4" --arg s "$5${reask:+; re-ask: $reask}" \
      --arg at "$(fresh "$(jq -r --arg id "$2" '.[] | select(.id == $id) | .askedAt' <<<"$cur")")" --arg w "$waits" --argjson o "${opts:-null}" \
      '{id: $id, askedAt: $at, question: $q, proposedDefault: $d, source: $s, answeredAt: null, answer: null}
       + (if $w == "" then {} else {waitsOn: $w} end) + (if $o == null then {} else {options: $o} end)')" ;;
  check)
    # check <id> <question> [<question asked beside it>...]: the picker hook
    # passes the questions before this one, so one asked twice in a single
    # picker is refused before any row is written.
    [ $# -ge 3 ] || usage
    id=$2 q=$3; shift 3
    for o in "$@"; do
      ! jq -ne --arg o "$o" --arg q "$q" "$SAME_Q"'$o | same_q($q)' >/dev/null \
        || { echo "decision: \"$q\" repeats \"$o\" in the same picker; ask it once." >&2; exit 3; }
    done
    [ -e "$L" ] || exit 0
    lock -s
    cur=$(fold) || exit 1
    gate "$cur" "$id" "$q" ;;
  answer)
    # --asked-at: answer only the snapshot the caller read. A hook that read
    # its open rows before a reopen must not close the reopened ask (reopen
    # always moves askedAt on).
    # --correct: replace a wrongly recorded answer; the old one goes to .history.
    asked="" correct=""
    if [ $# -eq 5 ] && [ "$4" = --asked-at ]; then asked=$5
    elif [ $# -eq 4 ] && [ "$4" = --correct ]; then correct=1
    else [ $# -eq 3 ] || usage; fi
    [ -n "$3" ] || die "an answer is required"
    lock -x
    cur=$(fold) || exit 1
    prev=$(jq -c --arg id "$2" '.[] | select(.id == $id)' <<<"$cur")
    [ -n "$prev" ] || die "unknown decision $2"
    if [ -n "$correct" ]; then
      ! jq -e '.answeredAt == null' <<<"$prev" >/dev/null || die "decision $2 is still open; answer it without --correct"
      append "$(jq -c --arg a "$3" --arg at "$(now)" --arg by "${USER:-unknown}" \
        '.history = (.history // []) + [{answer, answeredAt, correctedAt: $at, correctedBy: $by}] | .answer = $a' <<<"$prev")"
      exit 0
    fi
    jq -e '.answeredAt == null' <<<"$prev" >/dev/null || die "decision $2 is already answered (a wrongly recorded answer: add --correct)"
    [ -z "$asked" ] || jq -e --arg a "$asked" '.askedAt == $a' <<<"$prev" >/dev/null \
      || die "decision $2 was reopened after this answer read it"
    append "$(jq -c --arg a "$3" --arg at "$(now)" '.answeredAt = $at | .answer = $a' <<<"$prev")" ;;
  reopen)
    # reopen <id>: The owner's answer was not theirs (an Orca banner closed a
    # chat ask). The fresh askedAt keeps a prompt that arrived before the
    # reopen from closing it again; the wrong answer stays in the history. An
    # answered re-ask's grant is dropped: only a new --reask arms a picker.
    [ $# -eq 2 ] || usage
    lock -x
    cur=$(fold) || exit 1
    prev=$(jq -c --arg id "$2" '.[] | select(.id == $id)' <<<"$cur")
    [ -n "$prev" ] || die "unknown decision $2"
    ! jq -e '.answeredAt == null' <<<"$prev" >/dev/null || die "decision $2 is still open"
    append "$(jq -c --arg at "$(fresh "$(jq -r .askedAt <<<"$prev")")" '.askedAt = $at | .answeredAt = null | .answer = null
      | .source |= (index("; re-ask: ") as $i | if $i then .[:$i] else . end)' <<<"$prev")" ;;
  list)
    [ $# -eq 1 ] || usage
    lock -s
    fold ;;
  *) usage ;;
esac

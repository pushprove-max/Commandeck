# fence.sh -- sourced, never run. ONE FENCE RULE AND ONE HEADING RULE FOR EVERY READER OF MARKDOWN.
# A reviewer report's readers (surviving_severity in paths.sh, close-round.sh's stable ids, read-verdict.sh's verdict
# line) and a plan's (plan-check.sh, the Break lines of builder-codex-pass.sh) all put this ahead of their awk program,
# so no two of them can disagree about what is fixture text. Its own file so plan-check.sh, which runs outside any
# project, needs no paths.sh. A fence opens on a line of three or more backticks or tildes at 0-3 spaces of indent
# (four or more is indented code, D2), never inside an HTML block heading() holds open (DE10) and never on a backtick
# run with a backtick after it on the line, an inline span (DE11); it closes only on a line of the same character, at
# least as long, with nothing after it -- so a longer outer fence holds shorter delimiter text without closing.
# fence(line) returns 1 when the line opens a fence, 2 when it closes one and 0 otherwise; flen is non-zero while
# inside one.
# heading(line), called once per line, in order, after fence() and only when !flen (issue 640): sets hlvl (1-6, 0 for
# none) and htxt (the title, trimmed, closing #s dropped) and returns hlvl. It reads ATX at 0-3 spaces (`## T`,
# `## T ##`) and a setext underline (`===` 1, `---` 2) directly under a plain paragraph, whose whole text is the title
# (DE12). A paragraph is plain when its first line is no list item, quote, table row or 4-space indent; a list or quote
# paragraph runs through its lazy lines, so `- a` then `---` is a thematic break. No heading is read inside an HTML
# block (DE9). hold(line), called after heading(), returns what a section reader prints (lines ending "\n"): an open
# plain paragraph waits in pbuf, a setext underline drops it (they were its title), an ATX heading returns it without
# the heading line (DE13). hflush() returns what is left at the end or before a fence line (flush is plan-check's).
# hletters(t): the letters a reader sees in t, lowercased. One fixed list drops the source text CommonMark never
# displays: link and image destinations and titles `](...)`, full reference labels `][...]`, footnote marks `[^...]`,
# every `<...>` run (raw HTML, autolink brackets) and named entities `&name;`; numeric references `&#NN;` `&#xHH;` become
# their ASCII character. Emphasis, code spans and escapes show their own text, so every non-letter is then dropped
# (class-miss, passes 6-7). hgate(accept, key, how), after heading(): 1 when this line is a heading the gate opens on
# (htxt matches the regex accept; lowercased first when how holds "i"), 2 when it is not but its letters match key (how
# "eq": equal, the default; "start": begin with key; "has": contain every `&`-separated part of key), else 0. On 2 it
# writes `<file>:<line>: <why>` to stderr and appends it to ENVIRON["PP_GATE_STAMP"] when set, so the refusal is on
# record whatever the caller does with the read (pass 8). A reader stops on 2 or reads the section as closed; it never
# opens a section on 2.
# Shell side (class-miss, passes 8-9): pp_gate_init makes this run's empty stamp, pp_gate_awk runs a gate reader's awk,
# pp_gate_check refuses on a non-empty or missing stamp, pp_gate_act <cmd...> checks then runs an act that cannot be
# taken back, pp_gate_done removes the stamp. See each below.
PP_AWK_FENCE='
  function fence(line,   run, ch) {
    if (!match(line, /^[[:space:]]*(```+|~~~+)/)) return 0
    run = substr(line, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", run); ch = substr(run, 1, 1)
    if (!flen) {
      if (hblk != "" || line !~ /^ ? ? ?(```|~~~)/ || (ch == "`" && index(substr(line, RSTART + RLENGTH), "`"))) return 0
      fch = ch; flen = length(run); hpk = 0; ptxt = ""; return 1
    }
    if (ch == fch && length(run) >= flen && substr(line, RSTART + RLENGTH) ~ /^[[:space:]]*$/) { flen = 0; return 2 }
    return 0
  }
  function heading(line,   s, t, l, ind) {
    hlvl = 0; htxt = ""; hset = 0
    if (hblk != "") {
      if (hblk == "blank") { if (line ~ /^[ \t]*$/) hblk = "" }
      else if (index(tolower(line), hblk)) hblk = ""
      hpk = 0; ptxt = ""; return 0
    }
    if (line ~ /^[ \t]*$/) { hpk = 0; ptxt = ""; return 0 }
    match(line, /^ */); ind = RLENGTH; if (substr(line, ind + 1, 1) == "\t") ind = 4
    s = substr(line, ind + 1); t = s; sub(/[ \t]+$/, "", t); gsub(/[ \t]+/, " ", t)
    if (ind >= 4) { if (hpk == 1) ptxt = ptxt " " t; return 0 }
    if (hpk == 1 && s ~ /^(=+|-+)[ \t]*$/) {
      hlvl = (s ~ /^=/) ? 1 : 2; htxt = ptxt; hset = 1; hpk = 0; ptxt = ""; return hlvl
    }
    l = s; gsub(/[ \t]/, "", l)
    if (l ~ /^(\*\*\*+|---+|___+)$/) { hpk = 0; ptxt = ""; return 0 }
    if (s ~ /^#(#?#?#?#?#?)([ \t]|$)/) {
      match(s, /^#+/); hlvl = RLENGTH; t = substr(s, hlvl + 1)
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t ~ /^#+$/) t = ""; else sub(/[ \t]+#+$/, "", t)
      htxt = t; hpk = 0; ptxt = ""; return hlvl
    }
    l = tolower(s)
    if (l ~ /^<(script|pre|style|textarea)([ \t>]|$)/) { match(l, /^<[a-z]+/); hblk = "</" substr(l, 2, RLENGTH - 1) ">" }
    else if (l ~ /^<!--/) hblk = "-->"
    else if (l ~ /^<\?/) hblk = "?>"
    else if (l ~ /^<!\[cdata\[/) hblk = "]]>"
    else if (l ~ /^<![a-z]/) hblk = ">"
    else if (l ~ /^<\/?(address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)([ \t>]|\/>|$)/) hblk = "blank"
    else if (!hpk && l ~ /^<\/?[a-z][a-z0-9-]*([ \t][^<>]*)?\/?>[ \t]*$/) hblk = "blank"
    if (hblk != "") {
      if (hblk != "blank" && index(substr(l, 3), hblk)) hblk = ""
      hpk = 0; ptxt = ""; return 0
    }
    if (s ~ /^([-*+]|[0-9]+[.)])([ \t]|$)/ || s ~ /^[>|]/) { hpk = 2; ptxt = ""; return 0 }
    if (hpk == 1) ptxt = ptxt " " t; else if (!hpk) { hpk = 1; ptxt = t }
    return 0
  }
  function hold(line,   r) {
    if (hset) { pbuf = ""; return "" }
    if (hlvl) { r = pbuf; pbuf = ""; return r }
    if (hpk == 1) { pbuf = pbuf line "\n"; return "" }
    r = pbuf line "\n"; pbuf = ""; return r
  }
  function hflush(   r) { r = pbuf; pbuf = ""; return r }
  function hletters(t,   n, h, i, c) {
    while (match(t, /\]\([^)]*\)/)) t = substr(t, 1, RSTART) substr(t, RSTART + RLENGTH)
    while (match(t, /\]\[[^\]]*\]/)) t = substr(t, 1, RSTART) substr(t, RSTART + RLENGTH)
    while (match(t, /\[\^[^\]]*\]/)) t = substr(t, 1, RSTART - 1) substr(t, RSTART + RLENGTH)
    gsub(/<[^>]*>/, "", t)
    while (match(t, /&#[0-9]+;/)) {
      n = substr(t, RSTART + 2, RLENGTH - 3) + 0; c = (n > 31 && n < 127) ? sprintf("%c", n) : ""
      t = substr(t, 1, RSTART - 1) c substr(t, RSTART + RLENGTH)
    }
    while (match(t, /&#[xX][0-9A-Fa-f]+;/)) {
      h = tolower(substr(t, RSTART + 3, RLENGTH - 4)); n = 0
      for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
      c = (n > 31 && n < 127) ? sprintf("%c", n) : ""
      t = substr(t, 1, RSTART - 1) c substr(t, RSTART + RLENGTH)
    }
    gsub(/&[A-Za-z][A-Za-z0-9]*;/, "", t)
    t = tolower(t); gsub(/[^a-z]/, "", t); return t
  }
  function hgate(accept, key, how,   l, p, n, i, hit, w, st) {
    if (!hlvl) return 0
    if ((index(how, "i") ? tolower(htxt) : htxt) ~ accept) return 1
    l = hletters(htxt)
    if (index(how, "has")) { n = split(key, p, "&"); hit = 1; for (i = 1; i <= n; i++) if (!index(l, p[i])) hit = 0 }
    else if (index(how, "start")) hit = (substr(l, 1, length(key)) == key)
    else hit = (l == key)
    if (!hit) return 0
    w = (FILENAME == "" ? "-" : FILENAME) ":" FNR ": the heading `" $0 "` is not read as its gate section; write it in the accepted form (" accept ")"
    print w > "/dev/stderr"
    st = ENVIRON["PP_GATE_STAMP"]; if (st != "") { print w >> st; close(st) }
    return 2
  }'
# pp_gate_init -- make this run's refusal stamp, a new empty file, and export PP_GATE_STAMP. Every entry point that
# acts on a gate read calls it at start; an inherited stamp (a parent entry point's) is replaced, so a child never
# acts on, or stops for, its parent's reads.
pp_gate_init() {
  local d=${PP_SCRATCH:-${TMPDIR:-/tmp}}
  mkdir -p "$d" && PP_GATE_STAMP=$(mktemp "$d/gate-stamp.XXXXXX") || { echo "pp_gate_init: cannot make a stamp in $d" >&2; return 1; }
  export PP_GATE_STAMP
}
# pp_gate_awk <awk args...> -- run a gate reader's awk. A refusal hgate wrote, or an awk exit of 2 or more (a fatal
# error, an unreadable file) with no refusal written, is on the stamp; with no PP_GATE_STAMP a private one is used and
# removed. Returns 2 when this call recorded anything, else awk's status (1 stays a reader's plain no).
pp_gate_awk() {
  local st=${PP_GATE_STAMP:-} own= before=0 after rc=0
  if [ -z "$st" ]; then st=$(mktemp "${TMPDIR:-/tmp}/gate-stamp.XXXXXX") || return 2; own=1; fi
  [ ! -f "$st" ] || before=$(wc -l < "$st")
  PP_GATE_STAMP=$st awk "$@" || rc=$?
  after=0; [ ! -f "$st" ] || after=$(wc -l < "$st")
  if [ "$rc" -ge 2 ] && [ "$after" -le "$before" ]; then
    echo "${*: -1}: a gate read failed (awk exit $rc)" | tee -a "$st" >&2; after=$((before + 1))
  fi
  [ -z "$own" ] || rm -f "$st"
  [ "$after" -le "$before" ] || return 2
  return "$rc"
}
# pp_gate_check -- 0 when this run's stamp exists and is empty; else says each refusal (or the lost stamp) on stderr
# and returns 2. A missing stamp is lost state, never a clean read. With no PP_GATE_STAMP (not under an entry point) 0.
pp_gate_check() {
  [ -n "${PP_GATE_STAMP:-}" ] || return 0
  if [ ! -f "$PP_GATE_STAMP" ]; then echo "REFUSED: the gate refusal stamp $PP_GATE_STAMP is gone, so this run's reads cannot be trusted; run it again" >&2; return 2; fi
  [ -s "$PP_GATE_STAMP" ] || return 0
  echo "REFUSED: a gate read refused this run:" >&2; sed 's/^/  /' "$PP_GATE_STAMP" >&2; return 2
}
# pp_gate_act <cmd...> -- run one act that cannot be taken back, only after pp_gate_check passes; on a refusal the act
# does not run and 2 is returned (the caller maps it to its own stop: fail, exit 2 or exit 5).
pp_gate_act() { pp_gate_check || return 2; "$@"; }
# pp_gate_done -- remove this run's stamp at the entry point's normal end.
pp_gate_done() { [ -z "${PP_GATE_STAMP:-}" ] || rm -f "$PP_GATE_STAMP"; }

# json-clean.sh -- sourced by paths.sh and read-verdict.sh; defines pp_json_clean.
#
# Issue 660: one lone UTF-16 surrogate escape (`\ud83d` with no low half, as a model's cut-off emoji leaves) makes jq
# refuse the whole document ("Invalid \uXXXX\uXXXX surrogate pair escape"), so a seat report, an inbox or a drained
# batch read as empty or "cannot tell". pp_json_clean [file] copies stdin (or the file) to stdout with each lone
# `\uD800`-`\uDFFF` escape turned into `\ufffd` (U+FFFD); a valid high-low pair and an escaped backslash (`\\ud83d`)
# are kept. The row is never dropped, so a verdict beside the bad text is still read. With a file, a file holding no
# such escape is copied by `cat` after one grep, so a large session log costs one pass.
pp_json_clean() {
  if [ -n "${1:-}" ] && ! grep -qiE '\\ud[89a-f]' "$1" 2>/dev/null; then
    cat "$1"
    return
  fi
  perl -pe 's/\\(u[dD][89abAB][0-9a-fA-F]{2}\\u[dD][c-fC-F][0-9a-fA-F]{2}|u[dD][89a-fA-F][0-9a-fA-F]{2}|.)/length($1) == 5 ? "\\ufffd" : "\\$1"/ge' ${1:+"$1"}
}
# Run by name rather than sourced: --help or -h prints the header (issue 222's rule), anything else does nothing.
[ "${BASH_SOURCE[0]}" != "$0" ] || case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3 ;; esac

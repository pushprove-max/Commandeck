#!/usr/bin/env bash
# release-notes.sh <version> | --check [<file>] -- print that version's notes from CHANGELOG.md: the lines under its
# "## <version> -- <date>" heading, its ### topics as ##. It is the text update.sh shows and the body of a release.
# Exit 1 with a message when the changelog has no such section, and only then. Exit 2, after printing, when a line names a file, script, function, path, issue or commit.
# Exit 3 with a message for any other failure: the file cannot be read, the section has no notes, or the arguments are wrong.
# --check reads every version section of the file (default CHANGELOG.md) and prints each refused line on stderr.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
usage() { echo "usage: release-notes.sh <version> | --check [<file>]" >&2; exit 3; }
case ${1-} in
  --check) [ $# -le 2 ] || usage; MODE=check; FILE=${2:-$ROOT/CHANGELOG.md}; LABEL=${2:-CHANGELOG.md}; VER= ;;
  ''|-*) usage ;;
  *) [ $# -eq 1 ] || usage; MODE=notes; FILE=$ROOT/CHANGELOG.md; LABEL=CHANGELOG.md; VER=$1 ;;
esac
# One perl program: the rules need look-behind and \b, which awk and bash regexes do not share.
exec perl - "$MODE" "$VER" "$FILE" "$LABEL" <<'PERL'
use strict; use warnings;
my ($mode, $ver, $file, $label) = @ARGV;
open my $fh, '<', $file or do { print STDERR "release-notes: cannot read $file\n"; exit 3 };
my @L = <$fh>; chomp @L;
my $bad = 0;
sub refuse { my ($where, $why, $text) = @_; print STDERR "release-notes: $where: $why: $text\n"; $bad = 1; }
my $VERSION = qr/^## [0-9]+\.[0-9]+\.[0-9]+ -- /;
my $FILENAME = qr/(?<![\w.-])[\w.-]*\w\.(?:sh|py|js|mjs|ts|tsx|jq|md|json|jsonl|tsv|txt|log|yml|yaml|toml|html|css|png)\b/;
my $HASH = qr/(?<![\w-])(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?![\w-])/;
sub style {
  my ($where, $t) = @_;
  refuse($where, 'heading deeper than ###', $t) if $t =~ /^#{4,}\s/;
  refuse($where, 'file or script name', $t) if $t =~ $FILENAME;
  my $span = 0;
  while ($t =~ /`([^`]*)`/g) {
    my $s = $1;
    next if $s =~ m{^/[A-Za-z][\w:-]*(?:\s|$)};
    $span = 1 if $s =~ m{\S/} || $s =~ m{^(?:/|~/|\./)};
  }
  refuse($where, 'path in backticks', $t) if $span;
  (my $plain = $t) =~ s/`[^`]*`//g;
  refuse($where, 'path', $t) if $plain =~ m{(?:^|\s)(?:[~.]{0,2}/[\w.-]+/|[\w.-]+/[\w.-]+/[\w.-])};
  refuse($where, 'function name', $t) if $t =~ /\b[A-Za-z_]\w*\(\)/;
  refuse($where, 'issue reference', $t) if $t =~ /#\d+\b|\bCloses\b|\bRefs\b/;
  refuse($where, 'commit hash', $t) if $t =~ $HASH;
}
if ($mode eq 'check') {
  my $in = 0;
  for my $i (0 .. $#L) {
    if ($L[$i] =~ $VERSION) { $in = 1; next }
    style("$label:" . ($i + 1), $L[$i]) if $in;
  }
  exit($bad ? 1 : 0);
}
my ($s, $e);
for my $i (0 .. $#L) {
  if (!defined $s) { $s = $i if $L[$i] =~ /^## \Q$ver\E -- / }
  elsif ($L[$i] =~ $VERSION) { $e = $i; last }
}
$e = @L unless defined $e;
(print STDERR "release-notes: $file has no section for version $ver\n"), exit 1 unless defined $s;
my @n = ($s + 1 .. $e - 1);
shift @n while @n && $L[$n[0]] !~ /\S/;
pop @n while @n && $L[$n[-1]] !~ /\S/;
(print STDERR "release-notes: $file has no notes under version $ver\n"), exit 3 unless @n;
my @body;
for my $i (@n) { style("$label:" . ($i + 1), $L[$i]); (my $b = $L[$i]) =~ s/^###(\s)/##$1/; push @body, $b }
for my $k (0 .. $#body) { refuse('release body:' . ($k + 1), 'heading deeper than ## in a release body', $body[$k]) if $body[$k] =~ /^#{3,}\s/ }
print "$_\n" for @body;
exit($bad ? 2 : 0);
PERL

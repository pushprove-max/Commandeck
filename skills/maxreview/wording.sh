#!/usr/bin/env bash
# wording.sh adversarial|review [repo root] -- prints the review wording the Builder passes use, read live from
# scripts/builder-codex-pass.sh: adversarial prints the angles, review prints the closing focus, each with MANY, LENS and
# one severity line. Only the lines between the pass script's `# wording: begin` and `# wording: end` markers run, in a
# subshell, with HERE and die defined and BLOCK_LEVELS, OPEN and CLOSE empty (set outside the markers; no wording prints
# them). A missing script, a missing or doubled marker or a renamed wording variable is refused: no hand-written fallback.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
die() { echo "REFUSED: $*" >&2; exit 2; }
case ${1-} in adversarial|review) KIND=$1 ;; *) die "usage: wording.sh adversarial|review [repo root]" ;; esac
ROOT=${2:-$HERE/../..}
PASS_SH=$ROOT/scripts/builder-codex-pass.sh
[ -f "$PASS_SH" ] || die "no scripts/builder-codex-pass.sh under $ROOT; there is no hand-written fallback for the review wording"
[ "$(grep -c '^# wording: begin$' "$PASS_SH")" = 1 ] && [ "$(grep -c '^# wording: end$' "$PASS_SH")" = 1 ] \
  || die "$PASS_SH must carry exactly one '# wording: begin' and one '# wording: end' line"
BLOCK=$(awk '/^# wording: begin$/ { on = 1; next } /^# wording: end$/ { if (on) done = 1; on = 0; next } on' "$PASS_SH")
[ -n "$BLOCK" ] && [ "$(grep -n '^# wording: begin$' "$PASS_SH" | cut -d: -f1)" -lt "$(grep -n '^# wording: end$' "$PASS_SH" | cut -d: -f1)" ] \
  || die "$PASS_SH has its wording markers empty or out of order"
(
  set -u
  HERE=$ROOT/scripts
  BLOCK_LEVELS= OPEN= CLOSE=
  eval "$BLOCK"
  [ -n "${MANY:-}" ] && [ -n "${LENS:-}" ] || die "the wording block of $PASS_SH no longer sets MANY and LENS"
  if [ "$KIND" = adversarial ]; then
    [ -n "${ANGLES[*]+x}" ] || die "the wording block of $PASS_SH no longer sets ANGLES"
    printf '%s\n\n' "${ANGLES[@]}"
  else
    [ -n "${FOCUS_REVIEW:-}" ] || die "the wording block of $PASS_SH no longer sets FOCUS_REVIEW"
    printf '%s\n\n' "$FOCUS_REVIEW"
  fi
  printf '%s\n\n%s\n\n' "$MANY" "$LENS"
  echo 'Severity: critical, high, medium and low map to P0, P1, P2 and P3; only P0, P1 and P2 hold the review loop. Write each finding as one line with the exact failing input or command, and under it a line, Class search: rg <arguments>, a read-only rg search from the repository root whose hits are every place with the same mistake.'
)

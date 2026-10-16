#!/usr/bin/env bash
# Runs every area in $A/slices.tsv through one read-only roles.audit-auditor Codex session, 5 at a time.
# Called by run-audit.sh, which sets A (the scratch folder), HERE (this folder) and AUDITOR_ARGV (the role's command).
set -euo pipefail
A=${A:?run-audit.sh sets A} HERE=${HERE:?run-audit.sh sets HERE} AUDITOR_ARGV=${AUDITOR_ARGV:?run-audit.sh sets AUDITOR_ARGV}
COMMIT=$(cat "$A/commit.txt")
# The Findings header row the template gives the auditor, the one row the check below skips by its text.
HEADER=$(grep -m1 '^| ID |' "$HERE/PROMPT.template.md")
# run-audit.sh takes a nonempty output as a finished audit, so a failed auditor leaves none: not a partial file,
# not one from an earlier run in the same folder, nor one without the template's sections. Any failed area fails
# this script.
# Fills the prompt template, outside one() as verify.sh's check is: no here-document in an exported function.
read -r -d '' FILL <<'PY' || true
import sys
tpl, i, d, p, s, c, src = sys.argv[1:]
t = open(tpl).read()
for k, v in {'SLICE': i, 'DESC': d, 'PATHS': p, 'STANDARDS': s, 'COMMIT': c, 'SRC': src, 'ID': i.split('-')[0]}.items():
    t = t.replace('{{%s}}' % k, v)
print(t)
PY
one() {
  IFS=$'\t' read -r id desc paths standards <<<"$1"
  rm -f "$A/out/$id.md"
  python3 -c "$FILL" "$HERE/PROMPT.template.md" "$id" "$desc" "$paths" "$standards" "$COMMIT" "$A/src" > "$A/out/$id.prompt.md"
  rc=$?
  if [ "$rc" = 0 ]; then
    local -a auditor; mapfile -t auditor <<<"$AUDITOR_ARGV"
    env "${auditor[@]}" --skip-git-repo-check --ephemeral \
      -C "$A/src" -o "$A/out/$id.md" - < "$A/out/$id.prompt.md" > "$A/logs/$id.log" 2>&1
    rc=$?
  fi
  # Findings holds the table and nothing else: blank lines, the template's exact header row (cell padding aside), a
  # separator of dashes and rows that start `| <NN>-<n> |`, each id the area's and its own. verify.sh asks one verdict
  # of each id, so any other line (an indented row, a bullet, a sentence, a finding in a row shaped like the header)
  # is a finding no one would judge. A ## heading the template lacks would end
  # Findings and hide what follows it, so it fails too, as does a template heading out of its order or written twice.
  [ "$rc" != 0 ] || awk -v p="^[|] *${id%%-*}-[0-9]+ *[|]" -v hdr="$HEADER" 'function cells(s) {gsub(/[ \t]*[|][ \t]*/, "|", s); return s}
    BEGIN {hdr = cells(hdr); split("Summary|Findings|Reinvented wheels|Coverage", h, "|")
    for (i in h) rank[h[i]] = i}
    /^## /{t = $0; sub(/^## /, "", t); sub(/[ \t]+$/, "", t); bad = bad || !(t in rank) || rank[t] <= last; last = rank[t]
    f = (t == "Findings"); hf += f; hc += (t == "Coverage"); next}
    f && !/^[ \t]*$/ && cells($0) != hdr && !/^[|][-| :]*$/ {split($0, c, / *[|] */); if ($0 !~ p || seen[c[2]]++) bad = 1}
    END {exit bad || !hf || !hc}' "$A/out/$id.md" \
    || { echo "no Findings or Coverage section, a ## heading the template lacks, repeats or misorders, or a line in Findings that is not the template's header row, a separator or a row with its own id ${id%%-*}-<n>" >> "$A/logs/$id.log"; rc=1; }
  [ "$rc" = 0 ] || rm -f "$A/out/$id.md"
  echo "$id exit=$rc $(wc -c < "$A/out/$id.md" 2>/dev/null || echo 0) bytes $(date +%H:%M)"
  return "$rc"
}
export -f one; export A HERE COMMIT AUDITOR_ARGV HEADER FILL
# NUL-separated, no -I: xargs reads no quotes in a row and caps no row's length.
grep -v '^\s*$' "$A/slices.tsv" | tr '\n' '\0' | xargs -0 -n 1 -P 5 bash -c 'one "$1"' _
echo ALL-DONE

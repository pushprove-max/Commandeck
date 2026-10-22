#!/usr/bin/env bash
# platform-audit.test.sh -- the platform best-practice audit on a hand-written project. What this pins:
# run-audit.sh --dry-run names the areas it would audit and launches no agent; only the areas whose paths changed
# since the last audit are picked, by every path git names (quoted names, both sides of a move), and every area once
# the registry or areas file changes; every area's standards come from its .claude/paved-road.md row, and an area
# with no row, a changed file under an audited folder that no area holds, a missing registry, or a recorded commit
# that is not in the repo, or two areas with one id, fails loud instead of auditing the wrong set; a failed agent,
# or an output without the template's shape (a verdict needs a full row per finding and counts that match them), is
# never read as done; each run reads a fresh copy of HEAD, in a scratch folder a run made or a new or empty one; area text
# reaches the prompt as written; the verifier has read tools only; and
# both agents run as routing.json's audit roles say, never a model the scripts name.
# Run: bash scripts/__tests__/platform-audit.test.sh
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
D=$REAL/scripts/platform-audit
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export HOME=$T/home; mkdir -p "$HOME"
P=$T/proj; mkdir -p "$P/.claude" "$P/src/auth" "$P/src/services/billing" "$P/src/services/session" "$P/lib" "$P/scripts" "$P/docs"
for f in src/auth/login.ts src/services/billing/ledger.ts src/services/session/store.ts lib/stripe-client.ts package.json scripts/build.sh docs/README.md; do echo x > "$P/$f"; done
printf '01-auth\tOwner'"'"'s "login" and sessions\tsrc/auth, src/services (session, mfa)\n02-billing\tBilling and payments\tsrc/services (billing), lib (stripe)\n03-engineering\tRepo foundations\tpackage.json, scripts\n' > "$P/.claude/paved-road-areas.tsv"
{ cat "$REAL/templates/paved-road.md"
  printf '| 01-auth | OWASP ASVS V2, RFC 6238 TOTP | otplib |\n| 02-billing | Stripe integration best practices | the stripe SDK |\n| 03-engineering | Semantic versioning | node:test |\n'; } > "$P/.claude/paved-road.md"
git init -q -b main "$P" && git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -qm first
FIRST=$(git -C "$P" rev-parse HEAD)
# Stub agents and GitHub first on PATH: a dry run that reached any of them would leave a call here.
mkdir -p "$T/bin"
for b in codex claude gh; do printf '#!/bin/sh\necho "%s $*" >> %q\n' "$b" "$T/calls" > "$T/bin/$b"; chmod +x "$T/bin/$b"; done
audit() { (cd "$P" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$P" PATH="$T/bin:$PATH" COMMANDECK_AUDIT_DIR="$T/audit" "$@" bash "$D/run-audit.sh" --dry-run); }

audit COMMANDECK_AUDIT_STATE="$T/none" > "$T/all.out" 2>&1
check "with no audit recorded, a dry run lists every area and exits 0" "0 3" "$? $(grep -c '^area: ' "$T/all.out")"
check "a dry run launches no agent, calls no GitHub and writes no scratch folder" "no no" \
  "$([ -e "$T/calls" ] && echo yes || echo no) $([ -e "$T/audit" ] && echo yes || echo no)"
git -C "$P" rev-parse HEAD > "$T/head"
audit COMMANDECK_AUDIT_STATE="$T/head" > "$T/same.out" 2>&1
check "an audit recorded at HEAD leaves nothing to audit" "0 0 1" "$? $(grep -c '^area: ' "$T/same.out") $(grep -c 'no area changed' "$T/same.out")"
echo 0123456789abcdef0123456789abcdef01234567 > "$T/gone"
audit COMMANDECK_AUDIT_STATE="$T/gone" > "$T/gone.out" 2>&1
check "a recorded commit not in the repo fails loud, auditing nothing" "2 0 1" "$? $(grep -c '^area: ' "$T/gone.out") $(grep -c 'is not in this repo' "$T/gone.out")"
echo y >> "$P/src/services/billing/ledger.ts"; git -C "$P" -c user.name=t -c user.email=t@t commit -qam billing
echo "$FIRST" > "$T/first"
audit COMMANDECK_AUDIT_STATE="$T/first" > "$T/since.out" 2>&1
check "a change since the recorded audit picks only its area" "0 area: 02-billing" "$? $(grep '^area: ' "$T/since.out" | paste -sd' ' -)"
# Every changed path counts, as git has it: a name git would quote, and both sides of a rename.
commit() { git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -qm "$1"; git -C "$P" rev-parse HEAD^ > "$T/prev"; }
since() { audit COMMANDECK_AUDIT_STATE="$T/prev" 2>&1 | grep '^area: ' | paste -sd' ' -; }
echo x > "$P/src/auth/café.ts"; commit accent
check "a changed file whose name git quotes picks its area" "area: 01-auth" "$(since)"
mkdir -p "$P/docs/old"; git -C "$P" mv src/auth/login.ts docs/old/login.ts; commit move
check "a file moved out of an area picks the area it left" "area: 01-auth" "$(since)"
# A changed registry or areas file changes what every area is held to, so every area is audited again.
sed -i.bak 's/| Semantic versioning |/| Semantic versioning, Keep a Changelog |/' "$P/.claude/paved-road.md"; rm "$P/.claude/paved-road.md.bak"; commit standards
check "a changed registry picks every area" "area: 01-auth area: 02-billing area: 03-engineering" "$(since)"
printf '04-docs\tDocs\tdocs\n' >> "$P/.claude/paved-road-areas.tsv"; printf '| 04-docs | Diataxis | mkdocs |\n' >> "$P/.claude/paved-road.md"; commit area
check "a new area picks every area, the new one too" 4 "$(since | wc -w | awk '{print $1/2}')"
git -C "$P" rm -q .claude/paved-road.md; commit noreg
audit COMMANDECK_AUDIT_STATE="$T/none" > "$T/noreg.out" 2>&1
check "a project with no registry at HEAD fails, naming the template to start from" "2 1" "$? $(grep -c 'templates/paved-road.md' "$T/noreg.out")"
git -C "$P" reset -q --hard HEAD^

# Only the areas a change touches: a keyword path, a plain prefix, a file name anywhere, and a file in no area.
A=$P/.claude/paved-road-areas.tsv R=$P/.claude/paved-road.md
pick() { printf '%s\0' "$@" > "$T/changed"; python3 "$D/select-areas.py" "$A" "$R" "$T/changed" | cut -f1 | paste -sd' ' -; }
check "a billing service change picks billing only" "02-billing" "$(pick src/services/billing/credit-ledger.ts)"
check "a plain prefix picks its area" "01-auth" "$(pick src/auth/login.ts)"
check "a nested package.json picks engineering" "03-engineering" "$(pick web/package.json)"
check "a file outside every audited folder picks nothing" "" "$(pick other/README.md)"
check "two changes pick both areas, in the areas file's order" "01-auth 02-billing" "$(pick lib/stripe-client.ts src/services/mfa/totp.ts)"
# A changed file under a folder the areas audit, that no area holds (a new folder), fails the selection, naming it,
# instead of auditing nothing.
printf '%s\0' src/brand-new/thing.ts other/README.md > "$T/changed"
python3 "$D/select-areas.py" "$A" "$R" "$T/changed" > "$T/lost.out" 2> "$T/lost.err"
check "a changed file in no area under an audited folder fails, naming only it, and selects nothing" "1 1 0 0" \
  "$? $(grep -c 'src/brand-new/thing.ts' "$T/lost.err") $(grep -c 'other/README.md' "$T/lost.err") $(wc -c < "$T/lost.out" | tr -d ' ')"
python3 "$D/select-areas.py" "$A" "$R" | cut -f1,4 > "$T/std"
check "each area's standards are its registry row's" 1 "$(grep -c $'^02-billing\tStripe integration best practices$' "$T/std")"
grep -v '^| 02-billing ' "$R" > "$T/no-row.md"
python3 "$D/select-areas.py" "$A" "$T/no-row.md" > /dev/null 2> "$T/norow.err"
check "an area with no registry row fails, naming it" "1 1" "$? $(grep -c '02-billing has no Standards row' "$T/norow.err")"
# Two rows with one id would write one set of output files, and one area would vanish from a finished audit.
{ cat "$A"; printf '02-billing\tMore billing\tsrc/ledger\n'; } > "$T/dup.tsv"
python3 "$D/select-areas.py" "$T/dup.tsv" "$R" > /dev/null 2> "$T/dup.err"
check "two areas with one id fail, naming it" "1 1" "$? $(grep -c 'more than once: 02-billing' "$T/dup.err")"
: > "$T/empty.tsv"
python3 "$D/select-areas.py" "$T/empty.tsv" "$REAL/templates/paved-road.md" > /dev/null 2> "$T/empty.err"
check "the shipped empty registry with no areas fails, saying so" "1 1" "$? $(grep -c 'no area' "$T/empty.err")"

# A failed agent's output, partial or left from an earlier run in the same folder, must never read as done, or the
# audit records HEAD and that area is never retried. Live-run stubs: with STUB_FAIL set, the 01 auditor writes a
# partial file and fails, the 02 auditor fails over a stale file, and the 03 verifier writes a partial file and fails.
# A finished output is the template's shape: with STUB_FAIL=2 the 01 auditor's output has no Findings or Coverage
# section, and the 02 verifier leaves a finding unanswered, both exiting 0.
mkdir -p "$T/live-bin"
cat > "$T/live-bin/codex" <<SH
#!/usr/bin/env bash
echo "\$*" >> "$T/codex-args"
H=$(printf %q "$(grep '^| ID |' "$D/PROMPT.template.md")")
SH
cat >> "$T/live-bin/codex" <<'SH'
while [ $# -gt 0 ]; do [ "$1" != -o ] || o=$2; shift; done
case "${STUB_FAIL:-}:$o" in
  1:*01-auth.md) echo '# partial' > "$o"; exit 1 ;;
  1:*02-billing.md) exit 1 ;;
  2:*01-auth.md) echo '# audited' > "$o"; exit 0 ;;
  3:*01-auth.md) printf "## Findings\n$H\n|---|---|\n| AUTH-01 | P1 |\n## Coverage\nall\n" > "$o"; exit 0 ;;
  4:*01-auth.md) printf '## Findings\n | AUTH-01 | P1 |\n## Coverage\nReviewed: src/auth\n' > "$o"; exit 0 ;;
  5:*01-auth.md) printf "## Findings\n$H\n|---|---|\nAUTH-01 | P1 |\n## Coverage\nall\n" > "$o"; exit 0 ;;
  6:*01-auth.md) printf "## Findings\n$H\n|---|---|\n| 01-01 | P1 | missing auth |\n| 01-01 | P2 | duplicate charge |\n## Coverage\nall\n" > "$o"; exit 0 ;;
  7:*01-auth.md) printf '## Findings\n- [P1] Missing authorization -- src/auth/login.ts:1\n## Coverage\nReviewed: src/auth/login.ts\n' > "$o"; exit 0 ;;
  8:*01-auth.md) printf "## Findings\n$H\n|---|---|\n| 01-01 | P2 |\nAlso the login form posts the password over HTTP.\n## Coverage\nall\n" > "$o"; exit 0 ;;
  9:*01-auth.md) printf "## Findings\n## P1: Missing authorization\nLogin accepts another tenant's user ID.\n## Coverage\nReviewed: src/auth/login.ts\n" > "$o"; exit 0 ;;
  10:*01-auth.md) printf '## Summary\ns\n## Findings\n## Summary\n- [P1] Missing authorization -- src/auth/login.ts:1\n## Coverage\nReviewed: src/auth/login.ts\n' > "$o"; exit 0 ;;
  11:*01-auth.md) printf '## Findings\n## Summary\n- [P1] Missing authorization -- src/auth/login.ts:1\n## Coverage\nReviewed: src/auth/login.ts\n' > "$o"; exit 0 ;;
  12:*01-auth.md) printf '## Summary\ns\n## Findings\n| ID | P1 | Missing authorization at src/auth/login.ts:1 |\n## Reinvented wheels\nnone\n## Coverage\nReviewed: src/auth/login.ts\n' > "$o"; exit 0 ;;
  13:*01-auth.md) printf '## Findings\n| ID | P1 | Missing authorization at src/auth/login.ts:1 |\n|---|---|---|\n## Coverage\nReviewed: src/auth/login.ts\n' > "$o"; exit 0 ;;
  14:*01-auth.md) printf "## Findings\n$H\n|---|---|\n|-- P1 missing authorization --|\n## Coverage\nall\n" > "$o"; exit 0 ;;
esac
n=$(basename "$o" .md); n=${n%%-*}
printf '# x\n## Summary\ns\n## Findings\n%s\n|---|---|\n| %s-01 | P2 |\n| %s-02 | P3 |\n## Reinvented wheels\nnone\n## Coverage\nReviewed: all\n' "$H" "$n" "$n" > "$o"
SH
cat > "$T/live-bin/claude" <<SH
#!/usr/bin/env bash
echo "\$*" >> "$T/claude-args"
SH
cat >> "$T/live-bin/claude" <<'SH'
id=$(basename "$PWD"); echo "$id" >> "$(dirname "$(dirname "$PWD")")/verifier-calls"
# The verdict is the final message: the verifier writes no file.
rows=$(grep -oE '^\| [0-9]+-[0-9]+ ' "../../out/$id.md" | sed 's/$/| P2 | CONFIRMED | P2 | new | x:1 |/')
case "${STUB_FAIL:-}:$id" in
  1:03-engineering) jq -n '{result: "# partial"}'; exit 1 ;;
  2:02-billing) rows=$(head -1 <<<"$rows") ;;
esac
jq -n --arg r "$rows" '{result: ("# v\n| ID | Claimed |\n|---|---|\n" + $r + "\nconfirmed=2 partly=0 refuted=0 duplicates=0")}'
SH
printf '#!/bin/sh\necho []\n' > "$T/live-bin/gh"
chmod +x "$T/live-bin/"*
# Probe models: the agents must run what routing.json's audit roles name.
jq '.roles["audit-auditor"].model = "gpt-9.9-probe" | .roles["audit-verifier"].model = "verifier-probe"' "$REAL/config/routing.json" > "$T/routing.json"
L=$T/live; mkdir -p "$L/out"; echo '# stale' > "$L/out/02-billing.md"; : > "$L/.platform-audit"
live() { (cd "$P" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$P" COMMANDECK_ROUTING="$T/routing.json" \
  PATH="$T/live-bin:$PATH" COMMANDECK_AUDIT_DIR="$L" COMMANDECK_AUDIT_STATE="$T/live-state" "$@" bash "$D/run-audit.sh"); }
live STUB_FAIL=1 > "$T/live.out" 2>&1
check "a failed agent fails the audit and records no audit commit" "1 no" "$? $([ -e "$T/live-state" ] && echo yes || echo no)"
check "the report names each failed agent's output as missing and shows none of it" "1 1 1 0 0" \
  "$(grep -c 'MISSING out/01-auth.md' "$L/report.md") $(grep -c 'MISSING out/02-billing.md' "$L/report.md") $(grep -c 'MISSING verify/03-engineering.md' "$L/report.md") $(grep -c '# partial' "$L/report.md") $(grep -c '# stale' "$L/report.md")"
check "no verifier runs for an area whose audit failed" "0 0 1" \
  "$(grep -c '^01-' "$L/verifier-calls") $(grep -c '^02-' "$L/verifier-calls") $(grep -c '^03-' "$L/verifier-calls")"
check "the auditor runs routing's model and effort, read-only" "4 4 4" \
  "$(grep -c -- '--model gpt-9.9-probe' "$T/codex-args") $(grep -c 'model_reasoning_effort=xhigh' "$T/codex-args") $(grep -c -- '--sandbox read-only' "$T/codex-args")"
check "the verifier runs routing's model" 2 "$(grep -c -- '-p --model verifier-probe' "$T/claude-args")"
# The verifier reads; it cannot write or run anything, so nothing it reads can change the code or the reports.
check "the verifier is given read tools only" "2 0" "$(grep -c -- '--tools Read,Grep,Glob ' "$T/claude-args") $(grep -cE 'Write|Bash|Edit' "$T/claude-args")"
check "an area's text reaches its prompt as written, quotes and all" 1 "$(grep -c "Owner's \"login\" and sessions" "$L/out/01-auth.prompt.md")"
live STUB_FAIL=2 > "$T/live-bad.out" 2>&1
check "an output without the template's shape, or a verdict short of a finding, is no output" "1 no 1 1" \
  "$? $([ -e "$T/live-state" ] && echo yes || echo no) $(grep -c 'MISSING out/01-auth.md' "$L/report.md") $(grep -c 'MISSING verify/02-billing.md' "$L/report.md")"
# A finding whose id is not the area's would get no verifier row asked of it, so it would never be judged.
live STUB_FAIL=3 > "$T/live-id.out" 2>&1
check "an audit with a finding row not under the area's id is no output" "1 no 1" \
  "$? $([ -e "$T/live-state" ] && echo yes || echo no) $(grep -c 'MISSING out/01-auth.md' "$L/report.md")"
# Every row Markdown renders as a finding must pass that check: an indented row, or one with no leading pipe, too.
# Two findings with one id would share one verdict row, so one of them would never be judged. A finding written as
# a bullet or a sentence gets no verdict row asked of it either: under Findings only the table is read. A heading
# the template does not have would end Findings, so a finding under it would be read as no section's; so would a
# template heading written twice, or out of the template's order. Only the template's exact header row and a
# separator of dashes are skipped, so a finding written in either's place is caught too.
for c in "4 an indented finding row" "5 a finding row with no leading pipe" "6 two finding rows with one id" \
  "7 a bullet finding" "8 a finding in prose under the table" "9 a finding under its own ## heading" \
  "10 a finding under a second ## Summary" "11 a finding under a ## Summary after Findings" \
  "12 a finding in a header-shaped row" "13 a finding in a header row over a separator" "14 a finding in a separator-shaped row"; do
  live STUB_FAIL=${c%% *} > "$T/live-shape.out" 2>&1
  check "an audit with ${c#* } not under a unique area id is no output" "1 no 1" \
    "$? $([ -e "$T/live-state" ] && echo yes || echo no) $(grep -c 'MISSING out/01-auth.md' "$L/report.md")"
done
# Each run audits HEAD alone: a file deleted since an earlier run in the same folder is not in the copy.
git -C "$P" rm -q src/services/session/store.ts; git -C "$P" -c user.name=t -c user.email=t@t commit -qm drop
live > "$T/live2.out" 2>&1
check "the retry in the same folder, every agent succeeding, records HEAD" "0 $(git -C "$P" rev-parse HEAD)" "$? $(cat "$T/live-state" 2>/dev/null)"
check "and its copy holds no file deleted since the earlier run" "yes no" \
  "$([ -e "$L/src/src/services/billing/ledger.ts" ] && echo yes || echo no) $([ -e "$L/src/src/services/session/store.ts" ] && echo yes || echo no)"
# The run deletes and writes under the scratch folder, so a folder the caller names must be one a run made, or empty:
# never the project, a folder holding it, or any other folder with files in it.
echo wip > "$P/src/wip.ts"; mkdir -p "$T/full"; echo keep > "$T/full/keep.txt"; : > "$T/afile"
for dir in "$P" "$T" "$T/full" "$T/afile"; do
  rm -f "$T/codex-args"; live COMMANDECK_AUDIT_DIR="$dir" COMMANDECK_AUDIT_STATE="$T/none" > "$T/notmine.out" 2>&1
  check "a scratch folder no run made, with files in it ($dir), is refused before any delete or agent" "2 1 wip keep no" \
    "$? $(grep -c 'not a platform-audit scratch folder' "$T/notmine.out") $(cat "$P/src/wip.ts") $(cat "$T/full/keep.txt") $([ -e "$T/codex-args" ] && echo yes || echo no)"
done
rm "$P/src/wip.ts"
live COMMANDECK_AUDIT_DIR="$T/fresh" COMMANDECK_AUDIT_STATE="$T/st-fresh" > /dev/null 2>&1
check "a new scratch folder is made and marked as a run's" "0 yes" "$? $([ -e "$T/fresh/.platform-audit" ] && echo yes || echo no)"
mkdir "$T/empty"; live COMMANDECK_AUDIT_DIR="$T/empty" COMMANDECK_AUDIT_STATE="$T/st-empty" > /dev/null 2>&1
check "an empty scratch folder is used" 0 "$?"
# The copy and the recorded commit are HEAD's, so the areas are too: an area removed from the registry files but not
# committed is still audited, or HEAD would be recorded with that area's committed code never audited.
cp "$P/.claude/paved-road-areas.tsv" "$P/.claude/paved-road.md" "$T/"
grep -v '^02-billing' "$T/paved-road-areas.tsv" > "$P/.claude/paved-road-areas.tsv"; grep -v '^| 02-billing ' "$T/paved-road.md" > "$P/.claude/paved-road.md"
live COMMANDECK_AUDIT_DIR="$T/wipreg" COMMANDECK_AUDIT_STATE="$T/st-wipreg" > "$T/wipreg.out" 2>&1
check "an uncommitted removal of an area from the registry files still audits it" "0 1" "$? $(grep -c '^area: 02-billing$' "$T/wipreg.out")"
git -C "$P" checkout -q -- .claude

# A verdict is done only when every finding has a full row (a verdict word, a severity, a duplicate, evidence) and
# the counts line counts those rows; else HEAD would be recorded as audited with findings never judged.
V=$T/vunit; mkdir -p "$V/out" "$V/verify" "$V/vlogs" "$V/vrun"; echo c0 > "$V/commit.txt"; printf '01-auth\n' > "$V/slices.tsv"
printf '## Findings\n| ID | Severity |\n|---|---|\n| 01-01 | P1 |\n| 01-02 | P3 |\n## Coverage\nall\n' > "$V/out/01-auth.md"
printf '#!/bin/sh\njq -n --arg r "$VERDICT" '"'"'{result: $r}'"'"'\n' > "$T/vstub"; chmod +x "$T/vstub"
verdict() { VERDICT=$(printf '| ID | Claimed | Verdict | Severity now | Duplicate | Evidence |\n|---|---|---|---|---|---|\n%s\n## Notes\nnone\n%s\n' "$1" "$2") \
  A=$V HERE=$D VERIFIER_ARGV=$T/vstub bash "$D/verify.sh" > /dev/null 2>&1; echo "$([ $? = 0 ] && echo 0 || echo 1) $([ -s "$V/verify/01-auth.md" ] && echo kept || echo none)"; }
GOOD='| 01-01 | P1 | CONFIRMED | P1 | new | src/a.ts:3 real |
| 01-02 | P3 | **REFUTED** (deliberate: ruling) | P3 | #12 | src/b.ts:9 guarded |'
check "a full verdict whose counts match its rows is kept" "0 kept" "$(verdict "$GOOD" 'confirmed=1 partly=0 refuted=1 duplicates=1')"
check "rows holding only the finding id are no verdict" "1 none" "$(verdict $'| 01-01 |\n| 01-02 |' 'confirmed=0 partly=0 refuted=0 duplicates=0')"
check "a row with an unknown verdict word is no verdict" "1 none" \
  "$(verdict "$(sed 's/CONFIRMED/LIKELY/' <<<"$GOOD")" 'confirmed=1 partly=0 refuted=1 duplicates=1')"
check "a row with no evidence is no verdict" "1 none" \
  "$(verdict "$(sed 's/src\/a.ts:3 real //' <<<"$GOOD")" 'confirmed=1 partly=0 refuted=1 duplicates=1')"
check "a row with no severity is no verdict" "1 none" \
  "$(verdict "$(sed 's/| CONFIRMED | P1 |/| CONFIRMED | |/' <<<"$GOOD")" 'confirmed=1 partly=0 refuted=1 duplicates=1')"
check "a row with no duplicate answer is no verdict" "1 none" \
  "$(verdict "$(sed 's/| new |/| |/' <<<"$GOOD")" 'confirmed=1 partly=0 refuted=1 duplicates=2')"
check "a counts line that miscounts the verdicts is no verdict" "1 none" "$(verdict "$GOOD" 'confirmed=2 partly=0 refuted=0 duplicates=1')"
check "a counts line that miscounts the duplicates is no verdict" "1 none" "$(verdict "$GOOD" 'confirmed=1 partly=0 refuted=1 duplicates=0')"
check "a verdict with no counts line is no verdict" "1 none" "$(verdict "$GOOD" '')"
# A second row for one finding would silently replace the first, so a confirmed finding could leave the counts.
check "two verdict rows for one finding are no verdict, even with counts matching the last" "1 none" \
  "$(verdict "$GOOD"$'\n| 01-01 | P1 | REFUTED | P3 | new | src/a.ts:3 guarded |' 'confirmed=0 partly=0 refuted=2 duplicates=1')"
# An indented finding row is still a finding the verifier must answer.
printf '## Findings\n  | 01-01 | P1 |\n## Coverage\nall\n' > "$V/out/01-auth.md"
check "an indented finding row with no verdict row is no verdict" "1 none" "$(verdict '' 'confirmed=0 partly=0 refuted=0 duplicates=0')"
printf '## Findings\n| 01-01 | P1 |\n| 01-01 | P2 |\n## Coverage\nall\n' > "$V/out/01-auth.md"
check "two findings with one id are no verdict, even with a row counted twice" "1 none" \
  "$(verdict '| 01-01 | P2 | REFUTED | P2 | new | src/billing.ts:3 guarded |' 'confirmed=0 partly=0 refuted=2 duplicates=0')"

jq 'del(.roles["audit-auditor"])' "$REAL/config/routing.json" > "$T/routing.json"
rm -f "$T/codex-args"; live COMMANDECK_AUDIT_STATE="$T/none" > "$T/noroute.out" 2>&1
check "a routing file with no audit-auditor role fails before any agent runs" "2 1 no" \
  "$? $(grep -c 'audit-auditor' "$T/noroute.out") $([ -e "$T/codex-args" ] && echo yes || echo no)"
for s in run verify; do
  A=/dev/null HERE=$D AUDITOR_ARGV=codex VERIFIER_ARGV=claude bash "$D/$s.sh" > /dev/null 2>&1
  check "$s.sh with a scratch folder it cannot read fails" 1 "$([ $? -ne 0 ] && echo 1 || echo 0)"
  # xargs children get `one` through `export -f`; bash 5.2 (ubuntu CI) cannot re-read an exported function whose
  # here-document is followed by `||`, so every child failed there with `one: command not found`.
  check "$s.sh's exported function holds no here-document" 0 "$(awk '/^one\(\) \{/{f=1} f && /(^|[^<])<<[^<]/{n++} f && /^}/{f=0} END{print n+0}' "$D/$s.sh")"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# covers: scripts/fence.sh scripts/unit-drive.sh scripts/merge-unit-local.sh scripts/paths.sh scripts/builder-launch.sh scripts/builder-codex-pass.sh hooks/lib/project.sh
# Class-miss, passes 5-9: a gate read a heading, Break line or run-current answer it did not understand as absent (so a
# marked-up `## **Cuts**` closed an open cut's issue, a `## [Plan](#plan)` got a second Plan appended, run-current
# `"unexpected"` read as no run), and the refusals were then lost through callers (a pipe stage, `< <(...)`, `|| true`,
# an unchecked `$()`, `|| continue`, `return 0`) or checked before the act that needed them. Every reader must refuse
# a shape it does not read, on each read, and the refusal stamp must stop every act. Entry points are driven where the
# existing fixtures allow it (merge, builder-launch --from-plan); unit-drive's preflight and qopen and the pass script's
# table_gate and break_gate are called as functions (sed-extracted) with their acts stubbed or never reached.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
R=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$R"' EXIT
export PP_SCRATCH=$R/scratch; mkdir -p "$PP_SCRATCH" "$R/bin"; unset PP_GATE_STAMP COMMANDECK_RUN
. "$REAL/scripts/fence.sh"
fn() { sed -n "/^$2() {/,/^}/p" "$REAL/$1"; }
ev() { local f=$1; shift; while [ $# -gt 0 ]; do eval "$(fn "$f" "$1")"; shift; done; }
ev scripts/paths.sh pp_plan_section_paths pp_brief_plans pp_plan_stale
ev hooks/lib/project.sh pp_run_id_of pp_orca_run_id pp_is_main_pane
ev scripts/merge-unit-local.sh cut_scan cut_plan
ev scripts/unit-drive.sh preflight qopen; eval "$(sed -n '/^QSEC=/,/^  END/p' "$REAL/scripts/unit-drive.sh")"
RES=; seg() { RES+="${RES:+ | }$1"; }
fresh() { pp_gate_init; }                       # a new empty stamp, exported
snl() { wc -l < "$PP_GATE_STAMP" | tr -d ' '; } # lines on the stamp
rcof() { "$@" >/dev/null 2>&1; echo $?; }
hg() { printf '%s\n' "$4" | awk -v a="$1" -v k="$2" -v h="$3" "$PP_AWK_FENCE"'{ f = fence($0) } !f && !flen && heading($0) { printf "%s", hgate(a, k, h) }' 2>/dev/null; }
hgs() { local a=$1 k=$2 h=$3 o= t; shift 3; for t in "$@"; do o+=$(hg "$a" "$k" "$h" "$t"); done; printf '%s' "$o"; } # hgate per heading, in order

# 1. hgate per gate key: every marked-up form refuses (2), the accepted forms and controls read (1), a real section is 0.
seg "Q $(hgs '^Question for the owner$' 'question&owner' has '## **Question for the owner**' '### question for the owner:' '## <em>Question for the owner</em>' '## [Question for the owner](#q)' '## &#81;uestion for the owner' '## Question for the owner' '## Question for the owner ##')"
seg "Cuts $(hgs '^Cuts$' cuts eq '## **Cuts**' '## <em>Cuts</em>' '## [Cuts](#cuts)' '## [Cuts][c]' '## Cuts[^1]' '## Cuts' '## Template cuts')"
seg "Post $(hgs '^Post-merge$' postmerge start '## **Post-merge**' '## Post-merge steps' '## Post-merge' '## Post-merge ##')"
seg "Close $(hgs '^close as shipped$' closeasshipped 'i has' '## Do not close as shipped' '## **Close as shipped**' '## close AS shipped' '## Close as shipped')"
seg "Steps $(hgs '^Steps$' steps eq '## **Steps**' '## [Steps](#steps)' '## Steps')"
seg "Plan $(hgs '^Plan([[:space:]:]|$)' plan eq '## <em>Plan</em>' '## [Plan](#plan)' '## **Plan**' '## Plan: x' '## Plan')"
seg "Data $(hgs '^data design([[:space:]:]|$)' datadesign 'i start' '## **Data design**' '## data design' '## Data design')"

# 2. The real readers refuse, on both reads (a fresh stamp each read, as a new run makes one).
d=$R/rd; mkdir -p "$d/.claude/briefs" "$d/.claude/plans"; git init -q "$d"; git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
printf '## **Plan**\n\n.claude/plans/u.md\n' > "$d/plan-bad.md"; printf '## **Steps**\n\n- modify a.txt\n' > "$d/steps-bad.md"; printf '## Steps\n\n- modify a.txt\n' > "$d/steps-ok.md"
printf '# p\n\n## **Cuts**\n\n- C1 first #101\n- C2 second #102\n' > "$d/cuts-bad.md"; printf '# p\n\n## Cuts\n\n- C1 first #101\n- C2 second #102\n' > "$d/cuts-ok.md"
printf '# b\n\n## Plan\n\n.claude/plans/u.md\n' > "$d/brief-ok.md"; printf 'x\n\n## [Plan](#plan)\n\n.claude/plans/u.md\n' > "$d/brief-bad.md"
printf 'x\n\n## **Question for the owner**\n\nWhy?\n' > "$d/q-bad.md"; printf 'x\n\n## Question for the owner\n\nWhy?\n' > "$d/q-ok.md"
cuts() { local o; o=$( fail() { echo F; exit 1; }; WT=$d UNIT=u CUT_COUNT=; cut_scan "$1" "$d/out.md" 2>/dev/null || echo "rc$?"; echo "n$CUT_COUNT" ); echo "$(tr -d '\n' <<<"$o")/$(snl)"; }
twice() { local o= i; for i in 1 2; do fresh; o+="$("$@") "; done; printf '%s' "${o% }"; }
PLANF=$d/q-bad.md; ps() { rcof pp_plan_section_paths "$d/plan-bad.md"; }; st() { PP_MAIN=$d rcof pp_plan_stale HEAD HEAD "$1" x; }
seg "readers plan:$(twice ps) steps:$(twice st "$d/steps-bad.md") ok:$(twice st "$d/steps-ok.md") cuts:$(twice cuts "$d/cuts-bad.md") ok:$(twice cuts "$d/cuts-ok.md") q:$(twice rcof qopen)"
PLANF=$d/q-ok.md; seg "qopen ok:$(twice rcof qopen) awk-error:$(fresh; echo "$(rcof pp_gate_awk 'BEGIN { exit 3 }' /dev/null)/$(snl)")"
# pp_brief_plans and cut_plan: the refused Plan heading hides behind a pipe, and the plan is not found; the stamp holds the line.
printf '# plan\n\n## Cuts\n\n- C1 a #1\n- C2 b #2\n' > "$d/.claude/plans/u.md"
bp() { ( fail() { exit 1; }; WT=$d ROOT=$d UNIT=u BRIEF=$1 CUT_PLAN= CUT_NEXT= CUT_ISSUES=; cut_plan "$d"; echo "$(rcof pp_brief_plans "$1") plan=[$CUT_PLAN] stamp=$(snl) act=$(rcof pp_gate_act true)" ); }
fresh; seg "brief-plans $(bp "$d/brief-bad.md" 2>/dev/null) ok: $(fresh; bp "$d/brief-ok.md" 2>/dev/null)"
# The pass script: table_gate (Data design) and break_gate (`break:`) reach refusals_flush (rc 2, before staging or a commit).
TG=$(sed -n '/^REFUSALS=()$/p;/^refuse() { REFUSALS/p;/^refusals_flush()/,/^}/p;/^round_files()/,/^}/p;/^plan_rel()/p;/^plan_file()/p;/^evidence_section()/,/^}/p;/^table_gate()/,/^}/p;/^break_gate()/,/^}/p' "$REAL/scripts/builder-codex-pass.sh")
pass_gate() { ( die() { echo "REFUSED: $*" >&2; exit 2; }; WT=$d UNIT=g EV=$d/.claude/briefs/g-evidence.md; eval "$TG"; "$1"; refusals_flush ) >/dev/null 2>&1; echo $?; }
printf 'Plan: .claude/plans/g.md\n\n## **Data design**\n\n- the reply file: lives in a.json\n' > "$d/.claude/briefs/g.md"; : > "$d/.claude/briefs/g-evidence.md"
printf 'x\n\nbreak: t/a.test.sh -- c -- s\n' > "$d/.claude/plans/g.md"
g1=$(twice pass_gate table_gate); g2=$(twice pass_gate break_gate)
printf 'Plan: .claude/plans/g.md\n\n## data design\n\nnone: no state\n' > "$d/.claude/briefs/g.md"; printf 'x\n\nBreak: none\n' > "$d/.claude/plans/g.md"
seg "pass table:$g1 break:$g2 ok:$(twice pass_gate table_gate) $(twice pass_gate break_gate)"

# 3. Run-current: pp_run_id_of's allowlist and pp_is_main_pane's 2 on 4 or 5. orca-ide is a stub that prints $R/rc.
printf '#!/usr/bin/env bash\ncase "$2" in run-current) cat "%s/rc" ;; run-list) echo %s ;; esac\n' "$R" "'{\"result\":{\"runs\":[{\"id\":\"run_1\",\"coordinator_handle\":\"h\"}]}}'" > "$R/bin/orca-ide"; chmod +x "$R/bin/orca-ide"
pp_run_file() { echo "$R/runfile"; }
runs=('{"result":{"run":null}}' '{"result":{"run":{"id":"run_1"}}}' '{"result":{"run":"unexpected"}}' '{"result":{"run":{}}}' '{"result":{"runId":"r"}}' '')
o= p=; for j in "${runs[@]}"; do x=$(printf '%s' "$j" | pp_run_id_of 2>/dev/null); r=$?; o+="${x:+$x:}$r "; done
for j in "${runs[@]:2:3}" "${runs[0]}" "${runs[5]}"; do printf '%s' "$j" > "$R/rc"; m=; for i in 1 2; do rm -f "$R/runfile"; m+=$(ORCA_TERMINAL_HANDLE=h PATH=$R/bin:$PATH pp_is_main_pane 2>/dev/null; echo $?); done; p+="$m "; done
seg "run ${o% } main ${p% }"

# 4. Masking forms: the refusal sits on the stamp whatever the caller does with the read's status; the check and the act refuse.
rd() { pp_gate_awk "$PP_AWK_FENCE"'heading($0) { hgate("^Plan$", "plan", "eq") }' "$d/plan-bad.md"; }
probe() { rm -f "$R/ran"; echo "$([ "$(snl)" -gt 0 ] && echo 1 || echo 0)/$(rcof pp_gate_check)/$(rcof pp_gate_act touch "$R/ran")/$([ -e "$R/ran" ] && echo ran || echo no)"; }
m_pipe() { rd 2>/dev/null | cat; }; m_proc() { while read -r _; do :; done < <(rd 2>/dev/null); }; m_true() { rd 2>/dev/null || true; }
m_sub() { x=$(rd 2>/dev/null); }; m_cont() { local i; for i in 1; do rd 2>/dev/null || continue; done; }; m_ret() { rd 2>/dev/null; return 0; }
o=; for f in m_pipe m_proc m_true m_sub m_cont m_ret; do fresh; "$f"; o+="$(probe) "; done; seg "mask ${o% }"

# 5. Pass 9 orderings and stamp state. (a) refusal before a check; (b) read after a check, then an act; (c) re-read after an earlier act.
fresh; rd 2>/dev/null; a=$(rcof pp_gate_check)
fresh; pp_gate_check; rm -f "$R/A" "$R/B"; rd 2>/dev/null; b=$(rcof pp_gate_act touch "$R/A")/$([ -e "$R/A" ] && echo A || echo -)
fresh; pp_gate_act touch "$R/A"; rd 2>/dev/null; c=$(rcof pp_gate_act touch "$R/B")/$([ -e "$R/A" ] && echo A || echo -)$([ -e "$R/B" ] && echo B || echo -)
seg "order $a $b $c"
# Parent and child: a child's pp_gate_init replaces the inherited stamp; the parent refuses, a refusing child does not stop a clean parent.
fresh; rd 2>/dev/null; P=$PP_GATE_STAMP; ch=$( pp_gate_init; echo "$([ "$PP_GATE_STAMP" != "$P" ] && echo new) $(rcof pp_gate_check)" ); pr=$(rcof pp_gate_check)
fresh; P=$PP_GATE_STAMP; ch2=$( pp_gate_init; rd 2>/dev/null; rcof pp_gate_check ); pr2=$(rcof pp_gate_check)
seg "family child:$ch parent:$pr child-refused:$ch2 clean-parent:$pr2"
# The stamp removed between two runs (the second refuses again) and mid-run (after the read, before the check).
o=; for i in 1 2; do fresh; rd 2>/dev/null; o+="$(rcof pp_gate_check) "; rm -f "$PP_GATE_STAMP"; done
fresh; pp_gate_awk "$PP_AWK_FENCE"'heading($0) { hgate("^Plan$", "plan", "eq") }' "$d/brief-ok.md" 2>/dev/null; rm -f "$PP_GATE_STAMP"; rm -f "$R/A"
seg "stamp ${o% } mid:$(rcof pp_gate_check)/$(rcof pp_gate_act touch "$R/A")/$([ -e "$R/A" ] && echo ran || echo no)"

# 6. Entry points. unit-drive preflight (called as a function, its batch append the only act): `## [Plan](#plan)` refuses (2)
# with the batch unchanged; a batch with no Plan heading gets one appended.
printf 'Launch: new unit u\n' > "$d/aspec"; echo spec > "$d/jspec"; printf 'Order: x\n\n## [Plan](#plan)\n\n.claude/plans/u.md\n' > "$d/batch.md"; cp "$d/batch.md" "$d/batch.bad"; printf 'Order: x\n' > "$d/batch.ok"
pre() { ( UNIT=u BATCH=$1 ASPEC=$d/aspec JSPEC=$d/jspec DRY=0; preflight ) >/dev/null 2>&1; echo $?; }
cp "$d/batch.bad" "$d/batch.md"; fresh; pa=$(pre "$d/batch.md")/$(cmp -s "$d/batch.md" "$d/batch.bad" && echo same || echo changed)
fresh; pb=$(pre "$d/batch.ok")/$(grep -c '^## Plan$' "$d/batch.ok")
seg "preflight $pa ok:$pb"
# merge-unit-local.sh, driven: `## **Close as shipped**` over `- #9` stops in step 1 (twice), no squash, no issue close; a fenced
# `## Close as shipped` above `- #9` closes no issue.
MG=$( . "$REAL/scripts/__tests__/fixtures/merge-unit-local-setup.sh"
  mk ms; printf '# ms\n\n## The issues\n\n1. #9: one\n\n## **Close as shipped**\n\n- #9\n' > "$COMMANDECK_WORKSPACES/ms/.claude/briefs/ms.md"; go ms
  b=$(git -C "$REPO" rev-parse main); r1=$(merge ms); r2=$(merge ms)
  echo "$r1 $r2 $([ "$(git -C "$REPO" rev-parse main)" = "$b" ] && echo main-same) close=$(cat "$TMP/gh-calls" 2>/dev/null | grep -c 'issue close') failed=$(grep -c '^FAILED step 1 preconditions: a gate read refused' "$TMP/out")"
  mk mf; printf '# mf\n\n## The issues\n\n1. #8: one\n\n```\n## Close as shipped\n- #9\n```\n' > "$COMMANDECK_WORKSPACES/mf/.claude/briefs/mf.md"; go mf
  echo "fenced exit=$(merge mf) closed9=$(cat "$TMP/gh-calls" 2>/dev/null | grep -c 'issue close 9')" )
seg "merge $(tr '\n' ' ' <<<"$MG" | sed 's/ *$//')"
# builder-launch.sh --from-plan, driven (seat.sh, orca-ide, gh stubbed by the fixture): a refused Steps heading (stale_since, after
# which the plan commit would run) and a refused Plan heading in the batch leave nothing on main, open no Builder, exit 2, on each read.
BL=$( . "$REAL/scripts/__tests__/fixtures/builder-launch-resume-setup.sh"; cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"
  fpunit g1; printf '\n## **Steps**\n\n- modify scripts/paths.sh\n' >> "$WS/g1/.claude/plans/g1.md"; judged g1 GO 200
  fpunit g2; printf '\n## <em>Plan</em>\n\n.claude/plans/g2.md\n' >> "$WS/g2/.claude/briefs/g2-batch.md"; judged g2 GO 200
  o=; for u in g1 g1 g2 g2; do fp "$u"; o+="$RC:$(onmain "$u"):$(grep -c . "$T/seats") "; done; echo "${o% } commits=$(git -C "$P" rev-list --count main)" )
seg "launch $BL"

# Pass-script entry: the Break and table_gate refusals above end in refusals_flush (rc 2) before staging, so no commit; pass 4's
# act list (staging, commit, reviewer launch, hand-off) runs only through pp_gate_act, which test 5 shows refuses.
EXPECT='Q 2222211 | Cuts 2222210 | Post 2211 | Close 2211 | Steps 221 | Plan 22211 | Data 211'
EXPECT+=' | readers plan:2 2 steps:2 2 ok:0 0 cuts:F/1 F/1 ok:n2/0 n2/0 q:2 2 | qopen ok:0 0 awk-error:2/1'
EXPECT+=' | brief-plans 0 plan=[] stamp=2 act=2 ok: 0 plan=[.claude/plans/u.md] stamp=0 act=0 | pass table:2 2 break:2 2 ok:0 0 0 0'
EXPECT+=' | run 0 run_1:0 5 5 4 1 main 22 22 22 00 00 | mask 1/2/2/no 1/2/2/no 1/2/2/no 1/2/2/no 1/2/2/no 1/2/2/no'
EXPECT+=' | order 2 2/- 2/A- | family child:new 0 parent:2 child-refused:2 clean-parent:0 | stamp 2 2 mid:2/2/no | preflight 2/same ok:0/1'
EXPECT+=' | merge 1 1 main-same close=0 failed=1 fenced exit=3 closed9=0 | launch 2:none:0 2:none:0 2:none:0 2:none:0 commits=1'
check "every gate reader refuses a shape it does not read, on each read, whatever state is lost" "$EXPECT" "$RES"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

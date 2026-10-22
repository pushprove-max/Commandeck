#!/usr/bin/env bash
# checkpoint-context.py carry: a restart may not drop an open item it inherited (issue 252). An item counts as
# kept only where the new checkpoint's own text restates it or closes it; its "Carries open items of:" line is
# for recovery and keeps nothing, so a reworded item is reported, not carried silently.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
carry() { python3 "$REAL/scripts/checkpoint-context.py" carry "$1" "$2"; }

printf '## Queue\n- Plugin merge, then plugin second unit.\n' > "$TMP/base.md"
printf '## Queue\n- Plugin on owner answer.\n\n## Carried by reference\nCarries open items of: %s\n\n## Closed since last checkpoint\n- none\n' "$TMP/base.md" > "$TMP/new.md"
OUT=$(carry "$TMP/base.md" "$TMP/new.md"); RC=$?
check "a reworded item is dropped though the new checkpoint carries its file by reference" 1 "$RC"
check "and the dropped item is named" "- Plugin merge, then plugin second unit." "$OUT"

# The template's fresh-start "none" names no file: a base that says it, followed by one that restates its item, passes.
printf '## Queue\n- Plugin merge, then plugin second unit.\n\n## Carried by reference\nCarries open items of: none\n' > "$TMP/fresh.md"
check "Carries open items of: none is no reference" 0 "$(carry "$TMP/fresh.md" "$TMP/base.md" >/dev/null 2>&1; echo $?)"

# Issue 252: a close line closes one item, with a reason of its own. One line naming two items, or one reason
# pasted on many lines, is how a rewritten checkpoint dropped items and still passed.
cat > "$TMP/b2.md" <<'MD'
## Waiting on
- verdict from the alpha reviewer
- answer on the beta schema

## Queue (in order)
1. gamma report export
2. delta cache warmup
3. epsilon log rotation
MD
cat > "$TMP/n2.md" <<'MD'
## Waiting on
- verdict from the alpha reviewer

## Queue (in order)
1. epsilon log rotation

## Closed since last checkpoint
- none
MD
OUT=$(carry "$TMP/b2.md" "$TMP/n2.md"); RC=$?
check "a rewrite that drops three items fails" 1 "$RC"
check "and lists each dropped item" 3 "$(grep -c '^- ' <<<"$OUT")"
closed_with() { { cat "$TMP/n2.md"; printf '%s\n' "$@"; } > "$TMP/n2c.md"; carry "$TMP/b2.md" "$TMP/n2c.md"; }
check "one close line per item, each with its own reason, passes" 0 \
  "$(closed_with '- answer on the beta schema -- answered in the planning thread' '- gamma report export -- shipped in unit gamma' '- delta cache warmup -- dropped by the owner' >/dev/null; echo $?)"
OUT=$(closed_with '- gamma report export and delta cache warmup -- both shipped' '- answer on the beta schema -- answered'); RC=$?
check "one close line naming two items closes neither" "1 2" "$RC $(grep -cE '^- (gamma report export|delta cache warmup)$' <<<"$OUT")"
OUT=$(closed_with '- answer on the beta schema -- done' '- gamma report export -- done' '- delta cache warmup -- done'); RC=$?
check "one reason on three lines closes none" "1 3" "$RC $(grep -c '^- ' <<<"$OUT")"
OUT=$(closed_with '- answer on the beta schema -- see old.md' '- gamma report export -- shipped' '- delta cache warmup -- dropped'); RC=$?
check "a pointer line closes nothing" "1 1" "$RC $(grep -c 'beta schema' <<<"$OUT")"

# Issue 281: an item restated with a new status tail, a todo pointer, or closed in place is carried; a missing one is
# listed once however many times the chain repeats it.
cat > "$TMP/b3.md" <<'MD'
## Queue (in order)
- open: zeta migration plan -- reason: waiting on the schema
- eta dashboard fix = todo #2
- theta cleanup
- iota release notes
- iota release notes -- restated: still needed

## Todo list (the owner's on-screen checklist)
- [ ] kappa docs pass
MD
cat > "$TMP/n3.md" <<'MD'
## Queue (in order)
- zeta migration plan -- still open: schema answered, plan next
- CLOSED: theta cleanup -- removed in the last merge

## Todo list (the owner's on-screen checklist)
- [ ] kappa docs pass
- [>] eta dashboard fix review with the owner
MD
OUT=$(carry "$TMP/b3.md" "$TMP/n3.md"); RC=$?
check "restated tails, a todo pointer and a CLOSED: line carry; the missing item is listed once" "1 1 1" "$RC $(grep -c 'iota release notes' <<<"$OUT") $(grep -c '^- ' <<<"$OUT")"
sed 's/\[>\] eta dashboard fix/[>] other dashboard fix/' "$TMP/n3.md" > "$TMP/n3b.md"
check "a todo pointer whose todo starts with another word carries nothing" 1 "$(carry "$TMP/b3.md" "$TMP/n3b.md" | grep -c 'eta dashboard fix')"
# The pointed todo must name the whole subject: one that shares only its first word is another task.
sed 's/\[>\] eta dashboard fix review with the owner/[>] eta delete production backups/' "$TMP/n3.md" > "$TMP/n3c.md"
check "a todo pointer whose todo shares only the first word carries nothing" 1 "$(carry "$TMP/b3.md" "$TMP/n3c.md" | grep -c 'eta dashboard fix')"

# An item is kept by a new item of the same subject, and closed by a close line that starts with it: a line that
# only mentions it inside another item ("Q-9 discuss Q-3 later") keeps and closes nothing.
printf '## Queue (in order)\n- Q-3 widget export\n- deploy production\n' > "$TMP/k1.md"
printf '## Queue (in order)\n- Q-9 discuss Q-3 later\n- deploy production checklist for staging\n' > "$TMP/k2.md"
OUT=$(carry "$TMP/k1.md" "$TMP/k2.md"); RC=$?
check "a mention inside another item keeps neither Q-3 nor the plain item" "1 1 1" \
  "$RC $(grep -cx -- '- Q-3 widget export' <<<"$OUT") $(grep -cx -- '- deploy production' <<<"$OUT")"
printf '## Queue (in order)\n- deploy production\n\n## Closed since last checkpoint\n- Q-9 discuss Q-3 later -- moved to the next sprint\n' > "$TMP/k3.md"
check "a close line naming Q-3 mid-line closes nothing" "- Q-3 widget export" "$(carry "$TMP/k1.md" "$TMP/k3.md")"
# A close line that starts with a longer hyphenated subject (Q-3-staging) is about that subject, not Q-3.
printf '## Closed since last checkpoint\n- Q-3-staging -- cancelled the staging experiment\n- deploy production-staging -- dropped the staging copy\n' > "$TMP/k4.md"
OUT=$(carry "$TMP/k1.md" "$TMP/k4.md"); RC=$?
check "a close line for a hyphenated longer subject closes neither Q-3 nor the plain item" "1 1 1" \
  "$RC $(grep -cx -- '- Q-3 widget export' <<<"$OUT") $(grep -cx -- '- deploy production' <<<"$OUT")"

# A referenced file that cannot be read fails safe: the readable items still count, and the lost file is an item
# of its own the new checkpoint must restate or close.
printf '## Queue (in order)\n- ship release\n\nCarries open items of: %s\n' "$TMP/gone.md" > "$TMP/u1.md"
printf '## Queue (in order)\n- something new\n' > "$TMP/u2.md"
OUT=$(carry "$TMP/u1.md" "$TMP/u2.md"); RC=$?
check "an unreadable ancestor: the readable item and a carry-chain item are listed" "1 1 1" \
  "$RC $(grep -cx -- '- ship release' <<<"$OUT") $(grep -c '^- carry chain: cannot read the checkpoint .*gone.md' <<<"$OUT")"
check "the base itself unreadable still exits 2" 2 "$(carry "$TMP/gone.md" "$TMP/u2.md" >/dev/null; echo $?)"

# Issue 283: Q-<n> keys survive rewording, and Q-<n> -- <reason> closes one.
printf '## Queue (in order)\n- Q-3 widget export for the beta report\n- Q-4 cache warmup\n' > "$TMP/q1.md"
printf '## Queue (in order)\n- Q-3 beta report: the export is half done\n- Q-4 cache warmup\n' > "$TMP/q2.md"
printf '## Queue (in order)\n- Q-3 -- still open: export waits on review\n\n## Closed since last checkpoint\n- Q-4 -- merged with unit omega\n' > "$TMP/q3.md"
check "a Q-3 item reworded twice is carried, and Q-4 -- <reason> closes Q-4" "0 0" \
  "$(carry "$TMP/q1.md" "$TMP/q2.md" >/dev/null; echo $?) $(carry "$TMP/q2.md" "$TMP/q3.md" >/dev/null; echo $?)"
# r12: a close line that only repeats the item's own title, with or without its status tail, gives no reason.
printf '## Queue (in order)\n- Q-3 ship production\n- Q-5 deploy docs -- still open: waits on ops\n' > "$TMP/q4.md"
printf '## Queue (in order)\n- none\n\n## Closed since last checkpoint\n- Q-3 ship production\n- Q-5 deploy docs\n' > "$TMP/q5.md"
OUT=$(carry "$TMP/q4.md" "$TMP/q5.md"); RC=$?
check "a close line that repeats the item's title closes nothing" "1 1 1" \
  "$RC $(grep -c 'Q-3 ship production' <<<"$OUT") $(grep -c 'Q-5 deploy docs' <<<"$OUT")"

# Issue 283: an item ending "-- done when: <refs>" closes itself once every ref holds: an issue closed, a decision
# answered, a unit merged, a sha pushed. A ref that does not hold, or a lookup that fails, keeps it open.
M=$TMP/main; mkdir -p "$TMP/bin" "$TMP/home/.claude/checkpoints" "$M/.claude/metrics"
git init -q -b main "$M" && git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'feat(unit-omega): build'
git -C "$M" update-ref refs/remotes/origin/main HEAD
SHA=$(git -C "$M" rev-parse --short HEAD)
printf '{"id":"d-19990101-a","question":"q","proposedDefault":"x","source":"s","askedAt":"1999-01-01T00:00:00Z","answer":null,"answeredAt":null}\n{"id":"d-19990101-a","question":"q","proposedDefault":"x","source":"s","askedAt":"1999-01-01T00:00:00Z","answer":"yes","answeredAt":"1999-01-02T00:00:00Z"}\n{"id":"d-19990101-b","question":"q","proposedDefault":"x","source":"s","askedAt":"1999-01-01T00:00:00Z","answer":null,"answeredAt":null}\n' > "$M/.claude/metrics/decisions.jsonl"
printf '#!/bin/sh\ncase "$*" in *" 12 "*) echo CLOSED ;; *) echo OPEN ;; esac\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
printf '## Queue (in order)\n- ship the omega fix -- done when: #12, decision:d-19990101-a, unit-omega, %s\n- ship the psi fix -- done when: #12, decision:d-19990101-b\n' "$SHA" > "$TMP/a1.md"
printf '## Queue (in order)\n- something new\n' > "$TMP/a2.md"
OUT=$(cd "$M" && HOME=$TMP/home PATH="$TMP/bin:$PATH" python3 "$REAL/scripts/checkpoint-context.py" carry "$TMP/a1.md" "$TMP/a2.md"); RC=$?
check "every ref holding closes the item; one unanswered decision keeps the other" "1 0 1" \
  "$RC $(grep -c omega <<<"$OUT") $(grep -c psi <<<"$OUT")"
check "the close is one auto-closed line in clear-hook.log, with its evidence" 1 \
  "$(grep -c 'auto-closed: ship the omega fix -- .*#12 closed.*d-19990101-a answered.*unit-omega merged.*on origin/main' "$TMP/home/.claude/checkpoints/clear-hook.log")"
check "nothing is written to the checkpoint" 0 "$(grep -c auto-closed "$TMP/a2.md")"
# One Stop runs carry: a ref is looked up once per run however many items name it, and all lookups together stop at
# a bound. 100 items sharing #12 made 100 lookups, ~1,000 s when each hit its timeout. The timeouts are cut here.
OUT=$(cd "$M" && HOME=$TMP/home PATH="$TMP/bin:$PATH" timeout 60 python3 - "$REAL/scripts/checkpoint-context.py" "$TMP/slow" <<'EOF'
import contextlib, importlib.util, io, os, sys, time
spec = importlib.util.spec_from_file_location("cc", sys.argv[1]); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
cc.LOOKUP_S, cc.LOOKUP_TOTAL_S = 0.2, 1
d = sys.argv[2]; os.makedirs(f"{d}/bin")
open(f"{d}/bin/gh", "w").write(f"#!/bin/sh\necho x >> {d}/calls\nexec sleep 5\n"); os.chmod(f"{d}/bin/gh", 0o755)
os.environ["PATH"] = f"{d}/bin:" + os.environ["PATH"]
open(f"{d}/new.md", "w").write("## Queue (in order)\n- none\n")
res = []
for refs in (["#12"] * 100, [f"#{i}" for i in range(1, 101)]):
    open(f"{d}/calls", "w").close()
    open(f"{d}/base.md", "w").write("## Queue (in order)\n" + "".join(f"- Q-{i} ship it -- done when: {r}\n" for i, r in enumerate(refs, 1)))
    t, out = time.monotonic(), io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = cc.carry(f"{d}/base.md", f"{d}/new.md")
    calls = len(open(f"{d}/calls").read().split())
    res.append(f"{rc}:{out.getvalue().count('- Q-')}:{calls if calls == 1 else calls <= 7}:{time.monotonic() - t < 3}")
print(" ".join(res))
EOF
)
check "one ref shared by 100 items is looked up once; 100 timing-out refs stop at the total bound; all 100 kept open" \
  "1:100:1:True 1:100:True:True" "$OUT"
# Decision refs are lookups too: none starts past the bound and none reads on past it, and decisions.jsonl is read
# once per carry, however many decisions the items name (each one re-read the whole ledger, past the bound too).
DM=$TMP/dmain; mkdir -p "$DM/.claude/metrics"; git init -q "$DM"
OUT=$(cd "$DM" && HOME=$TMP/home timeout 60 python3 - "$REAL/scripts/checkpoint-context.py" "$DM" <<'EOF'
import builtins, contextlib, importlib.util, io, sys, time
spec = importlib.util.spec_from_file_location("cc", sys.argv[1]); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
d = sys.argv[2]
open(f"{d}/.claude/metrics/decisions.jsonl", "w").write("".join(f'{{"id":"d-{i}","answer":"yes"}}\n' for i in range(1, 10001)))
reads, slow = [0], [False]
def counted(p, *a, **k):
    if str(p).endswith("decisions.jsonl"):
        reads[0] += 1
        if slow[0]:
            return contextlib.nullcontext(time.sleep(0.01) or f'{{"id":"d-{i}","answer":"yes"}}\n' for i in range(1, 101))
    return builtins.open(p, *a, **k)
cc.open = counted
open(f"{d}/base.md", "w").write("## Queue (in order)\n" + "".join(f"- Q-{i} ship it -- done when: decision:d-{i}\n" for i in range(1, 101)))
open(f"{d}/new.md", "w").write("## Queue (in order)\n- none\n")
with contextlib.redirect_stdout(io.StringIO()):
    rc = cc.carry(f"{d}/base.md", f"{d}/new.md")
res = [rc, reads[0], cc.holds("decision:d-1", d, time.monotonic() - 1)]
slow[0], t = True, time.monotonic()
res += [cc.holds("decision:d-100", d, t + 0.2), time.monotonic() - t < 0.5]
print(*res)
EOF
)
check "100 decisions answered close with one ledger read; an expired bound reads none; a slow read stops at the bound" \
  "0 1 None None True" "$OUT"

# Issue 283: dedupe flattens a stacked checkpoint's chain into it, one line per subject, keeps a backup, re-stamps the
# restart marker, refuses a second run, and a later drop is still caught.
U='## Queue (left unresolved at the restart: restate or close each, one line per item, with its own reason)'
printf '## Queue (in order)\n- rho old item\n' > "$TMP/s0.md"
printf '## Waiting on\n- sigma verdict\n\n%s\n- tau export\n- sigma verdict -- still open: pending\n\n## Queue (in order)\n- upsilon cleanup\n- upsilon cleanup\n\n%s\n- tau export\n- phi notes\n\n## Gotchas learned this session\n- none\n\n%s\n- phi notes -- restated: still due\n\nCarries open items of: %s\n' "$U" "$U" "$U" "$TMP/s0.md" > "$TMP/s1.md"
cksum < "$TMP/s1.md" > "$TMP/s1.md.restarted"
python3 "$REAL/scripts/checkpoint-context.py" dedupe "$TMP/s1.md" >/dev/null; RC=$?
check "dedupe exits 0, keeps a backup and leaves one unresolved Queue heading" "0 yes 1" \
  "$RC $([ -f "$TMP/s1.md.bak" ] && echo yes) $(grep -c '^## Queue (left unresolved' "$TMP/s1.md")"
check "one line per subject, the chain's own item flattened in" "1 1 1 1 1 1" \
  "$(for w in rho sigma tau upsilon phi; do grep -c "^- $w" "$TMP/s1.md"; done | paste -sd' ') $(grep -c 'Carries open items of: none' "$TMP/s1.md")"
check "the restart marker holds the new checksum" "$(cksum < "$TMP/s1.md")" "$(cat "$TMP/s1.md.restarted")"
check "a second dedupe refuses while the backup exists" 1 "$(python3 "$REAL/scripts/checkpoint-context.py" dedupe "$TMP/s1.md" >/dev/null 2>&1; echo $?)"
grep -v '^- tau' "$TMP/s1.md" > "$TMP/s2.md"
check "a drop after the dedupe is still caught" "- tau export" "$(carry "$TMP/s1.md" "$TMP/s2.md")"

# Issue 283: the walk stops after ten generations; aged lists what that cut drops.
printf '## Queue (in order)\n- chi oldest item\n' > "$TMP/g11.md"
for g in $(seq 10 -1 1); do printf '## Queue (in order)\n- generation %s item\n\nCarries open items of: %s\n' "$g" "$TMP/g$((g + 1)).md" > "$TMP/g$g.md"; done
OUT=$(python3 "$REAL/scripts/checkpoint-context.py" aged "$TMP/g1.md")
check "aged on an eleven-generation chain lists the eleventh's item only, with its carried-unseen tail" "1 0" \
  "$(grep -c '^- chi oldest item -- carried unseen: 11$' <<<"$OUT") $(grep -c 'generation' <<<"$OUT")"
# A missing file past the walk does not drop the readable older items: each is listed, and so is the missing file.
printf '## Queue (in order)\n- chi oldest item\n\nCarries open items of: %s\n' "$TMP/g12.md" > "$TMP/g11.md"
OUT=$(python3 "$REAL/scripts/checkpoint-context.py" aged "$TMP/g1.md"); RC=$?
check "aged past a missing twelfth exits 0, listing the eleventh's item and the missing file" "0 1 1" \
  "$RC $(grep -c '^- chi oldest item -- carried unseen: 11$' <<<"$OUT") $(grep -c '^- carry chain: cannot read the checkpoint .*g12.md' <<<"$OUT")"
printf '## Queue (in order)\n- chi oldest item\n' > "$TMP/g11.md"
# dedupe cuts the references, so it flattens the whole chain, not the carry walk's ten generations.
python3 "$REAL/scripts/checkpoint-context.py" dedupe "$TMP/g1.md" >/dev/null
check "dedupe of an eleven-generation chain keeps the eleventh's item" 1 "$(grep -cx -- '- chi oldest item' "$TMP/g1.md")"
# A chain grows a file per restart: past the interpreter's recursion limit the walk must still finish, or the
# stop hook cannot restart and dedupe cannot recover.
mkdir "$TMP/long"
printf '## Queue (in order)\n- generation 1100 item\n' > "$TMP/long/g1100.md"
for g in $(seq 1099 -1 1); do printf '## Queue (in order)\n- generation %s item\n\nCarries open items of: g%s.md\n' "$g" "$((g + 1))" > "$TMP/long/g$g.md"; done
OUT=$(python3 "$REAL/scripts/checkpoint-context.py" aged "$TMP/long/g1.md" 2>&1); RC=$?
check "aged on an 1100-generation chain exits 0 and lists generations 11 to 1100, each at its own depth" "0 1090 1 1" \
  "$RC $(grep -c '^- generation [0-9]* item -- carried unseen: [0-9]*$' <<<"$OUT") $(grep -cx -- '- generation 11 item -- carried unseen: 11' <<<"$OUT") $(grep -cx -- '- generation 1100 item -- carried unseen: 1100' <<<"$OUT")"
python3 "$REAL/scripts/checkpoint-context.py" dedupe "$TMP/long/g1.md" >/dev/null 2>&1; RC=$?
check "dedupe of an 1100-generation chain exits 0 and keeps the oldest item" "0 1" "$RC $(grep -cx -- '- generation 1100 item' "$TMP/long/g1.md")"
# The walk's memory must grow with the chain, not its square, for every shape a chain has taken, with many items per
# checkpoint (one item per file hid masks sized by the chain, per key and per file: 91 MiB at 1,600 files, pass 24).
# Each shape has 20 items per file and is run at N and 2N on both walks: the peak may grow at most 2.5x (quadratic is
# x4). Shapes: a chain; the chain where each file closes one item of the next (ended keys); Sol's r22 graph (f1 carries
# every file, each other file the next); a hub (root carries n files that all carry one file); two-next-files, without
# and with a back-edge to f1; r22's graph with each file closing the next one's item, and a chain whose items one
# side file closes (the generation search kept every open key at every file: 3.6 / 13.6 / 52 MiB at 200 / 400 / 800
# files, pass r1). Per owner ruling the growth class is closed at this bound (see the evidence file).
OUT=$(timeout 600 python3 - "$REAL/scripts/checkpoint-context.py" "$TMP/shapes" <<'EOF'
import importlib.util, math, os, sys, tracemalloc
spec = importlib.util.spec_from_file_location("cc", sys.argv[1]); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
def write(d, g, rs, closes=()):
    items = "".join(f"- f{g} item {i}\n" for i in range(20))
    closed = "\n## Closed since last checkpoint\n" + "".join(f"- {c} -- shipped in round {g}.{i}\n" for i, c in enumerate(closes)) if closes else ""
    open(f"{d}/f{g}.md", "w").write(f"## Queue (in order)\n{items}{closed}" + "".join(f"\nCarries open items of: f{r}.md" for r in rs) + "\n")
# Each shape writes f1..fN and returns (items, farthest generation) on the whole walk and on the ten-generation walk.
def chain(d, n):
    for g in range(1, n + 1):
        write(d, g, [g + 1][:g < n])
    return (20 * n, n - 1), (200, 9)
def closing(d, n):
    for g in range(1, n + 1):
        write(d, g, [g + 1][:g < n], [f"f{g + 1} item 0"][:g < n])
    return (20 * n - (n - 1), n - 1), (191, 9)
# f1 carries every file, each other file the next and closes the next one's item 0: every key ended, all open at f1.
def fanclosing(d, n):
    for g in range(1, n + 1):
        write(d, g, list(range(2, n + 1)) if g == 1 else [g + 1][:g < n], [f"f{g + 1} item 0"][:1 < g < n])
    return (20 * n, 1), (20 * n, 1)
# f1 carries a chain f2..f(n-1) and fn, which carries f2 and closes every chain file's item 0: open only along the chain.
def detour(d, n):
    for g in range(2, n):
        write(d, g, [g + 1][:g < n - 1])
    write(d, n, [2], [f"f{g} item 0" for g in range(2, n)])
    write(d, 1, [2, n])
    return (20 * n, n - 2), (220, 9)
def fan(d, n):
    for g in range(1, n + 1):
        write(d, g, list(range(2, n + 1)) if g == 1 else [g + 1][:g < n])
    return (20 * n, 1), (20 * n, 1)
def hub(d, n):
    write(d, n, [])
    for k in range(2, n):
        write(d, k, [n])
    write(d, 1, range(2, n))
    return (20 * n, 2), (20 * n, 2)
def ladder(d, n, back=False):
    for g in range(1, n + 1):
        write(d, g, [h for h in (g + 1, g + 2) if h <= n] + ([1] if back and g == n else []))
    return (20 * n, math.ceil((n - 1) / 2)), (380, 9)
def cyclic(d, n):
    return ladder(d, n, True)
out = []
for shape, sizes in ((chain, (800, 1600)), (closing, (400, 800)), (fan, (800, 1600)), (hub, (400, 800)),
                     (ladder, (800, 1600)), (cyclic, (800, 1600)), (fanclosing, (400, 800)), (detour, (400, 800))):
    for which, depth in ((0, sys.maxsize), (1, cc.MAX_DEPTH)):
        peaks = []
        for n in sizes:
            d = f"{sys.argv[2]}-{shape.__name__}-{which}-{n}"; os.makedirs(d)
            want = shape(d, n)[which]
            tracemalloc.start()
            got = cc.effective(f"{d}/f1.md", depth)
            peaks.append(tracemalloc.get_traced_memory()[1]); tracemalloc.stop()
            assert (len(got), max(g for _, _, g in got)) == want, (shape.__name__, depth, n, len(got), want)
        out.append("linear" if peaks[1] <= 2.5 * peaks[0] else f"superlinear {shape.__name__} {depth} {[p >> 20 for p in peaks]} MiB")
print(" ".join(out))
EOF
)
check "every shape, 20 items per file, both walks: all items at their generation, peak memory at most 2.5x on doubling" \
  "linear linear linear linear linear linear linear linear linear linear linear linear linear linear linear linear" "$OUT"
# Operations grow with the chain too, not only memory: a search from the root per ended key made 39,800 / 159,600
# visits at 200 / 400 files where each file closes the next one's only item. Lines run inside the walk are counted, on
# that chain, on r22's graph with the same closes (every key open at f1 and searched) and on a chain whose items a side
# file closes (every key searched down the chain).
OUT=$(timeout 120 python3 - "$REAL/scripts/checkpoint-context.py" "$TMP/ops" <<'EOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("cc", sys.argv[1]); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
def write(d, k, rs, closes=()):
    closed = "\n## Closed since last checkpoint\n" + "".join(f"- {c} item -- shipped in generation {k}.{i}\n" for i, c in enumerate(closes)) if closes else ""
    open(f"{d}/f{k}.md", "w").write(f"## Queue (in order)\n- f{k} item\n{closed}" + "".join(f"\nCarries open items of: f{r}.md" for r in rs) + "\n")
def closing(d, n):
    for k in range(1, n + 1):
        write(d, k, [k + 1][:k < n], [f"f{k + 1}"][:k < n])
    return [("f1 item", 0)]
def fanclosing(d, n):
    for k in range(1, n + 1):
        write(d, k, list(range(2, n + 1)) if k == 1 else [k + 1][:k < n], [f"f{k + 1}"][:1 < k < n])
    return [("f1 item", 0)] + [(f"f{k} item", 1) for k in range(2, n + 1)]
def detour(d, n):
    for k in range(2, n):
        write(d, k, [k + 1][:k < n - 1])
    write(d, n, [2], [f"f{k}" for k in range(2, n)])
    write(d, 1, [2, n])
    return [("f1 item", 0), ("f2 item", 1), (f"f{n} item", 1)] + [(f"f{k} item", k - 1) for k in range(3, n)]
out = []
for shape in (closing, fanclosing, detour):
    ops = []
    for n in (200, 400):
        d = f"{sys.argv[2]}-{shape.__name__}-{n}"; os.makedirs(d)
        want = shape(d, n)
        count = [0]
        def trace(frame, event, arg):
            if frame.f_code is cc.effective.__code__:
                count[0] += 1
                return lambda f, e, a: count.__setitem__(0, count[0] + 1)
        sys.settrace(trace); got = cc.effective(f"{d}/f1.md", sys.maxsize); sys.settrace(None)
        assert sorted((i, g) for _, i, g in got) == sorted(want), (shape.__name__, got[:5])
        ops.append(count[0])
    out.append("linear" if ops[1] <= 2.5 * ops[0] else f"superlinear {shape.__name__} {ops}")
print(" ".join(out))
EOF
)
check "each file closing the next one's item, r22's graph with those closes, a side file closing a chain: walk operations at most 2.5x on doubling" \
  "linear linear linear" "$OUT"
# Pass r2: R carries B1..BN, each Bi closes item i and carries Ti and L, each Ti carries L, L owns items 1..N. Every
# key search kept a distinct N-key mask per Ti (N^2/8 bytes: 2.2 MiB more held at 3,200 branches), and its peak hid
# under the reads' own memory. Measured here: what the closes add to the memory the walk still holds as it returns,
# against the same graph closing other subjects. All items stay open at the root (each branch keeps the others').
OUT=$(timeout 300 python3 - "$REAL/scripts/checkpoint-context.py" "$TMP/r2shape" 3200 <<'EOF'
import importlib.util, os, sys, tracemalloc
spec = importlib.util.spec_from_file_location("cc", sys.argv[1]); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
n, held, out = int(sys.argv[3]), [0], []
def trace(frame, event, arg):
    if frame.f_code is cc.effective.__code__:
        frame.f_trace_lines = False
        return lambda f, e, a: held.__setitem__(0, tracemalloc.get_traced_memory()[0]) if e == "return" else None
for subject in ("other", "item"):
    d = f"{sys.argv[2]}-{subject}"; os.makedirs(d)
    w = lambda name, body: open(f"{d}/{name}.md", "w").write(body)
    w("L", "## Queue (in order)\n" + "".join(f"- item {i}\n" for i in range(1, n + 1)))
    for i in range(1, n + 1):
        w(f"T{i}", "Carries open items of: L.md\n")
        w(f"B{i}", f"## Closed since last checkpoint\n- {subject} {i} -- shipped in branch {i}\n\nCarries open items of: T{i}.md\nCarries open items of: L.md\n")
    w("R", "".join(f"Carries open items of: B{i}.md\n" for i in range(1, n + 1)))
    tracemalloc.start(); sys.settrace(trace); got = cc.effective(f"{d}/R.md", sys.maxsize); sys.settrace(None); tracemalloc.stop()
    assert sorted(g for *_, g in got) == [2] * n, (subject, len(got))
    out.append(held[0])
print("linear" if out[1] - out[0] < 64 * (3 * n + 2) else f"superlinear {(out[1] - out[0]) >> 10} KiB")
EOF
)
check "Sol's r2 branches, 3,200 of them: all items open at generation 2, the closes hold under 64 bytes per file" "linear" "$OUT"
# Several reference lines per file are kept, by ruling. A ladder of files each carrying the next
# twice is walked once per file: a result forgotten before its last referrer reads it makes the walk 2^40 reads.
mkdir "$TMP/ladder"
printf '## Queue (in order)\n- rung 40 item\n' > "$TMP/ladder/r40.md"
for g in $(seq 39 -1 1); do printf '## Queue (in order)\n- rung %s item\n\nCarries open items of: r%s.md\nCarries open items of: r%s.md\n' "$g" "$((g + 1))" "$((g + 1))" > "$TMP/ladder/r$g.md"; done
OUT=$(timeout 20 python3 "$REAL/scripts/checkpoint-context.py" aged "$TMP/ladder/r1.md" 2>&1); RC=$?
check "aged on a 40-rung two-reference ladder exits 0 in time and lists rungs 11 to 40 once each" "0 30 1" \
  "$RC $(grep -c '^- rung [0-9]* item -- carried unseen: [0-9]*$' <<<"$OUT") $(grep -cx -- '- rung 40 item -- carried unseen: 40' <<<"$OUT")"
# Siblings each get a shared file's whole result: one sibling's closure does not hide the other's open item.
printf '## Queue (in order)\n- omega shared item\n' > "$TMP/d.md"
printf '## Queue (in order)\n- beta own item\n\n## Closed since last checkpoint\n- omega shared item -- shipped in beta\n\nCarries open items of: d.md\n' > "$TMP/b.md"
printf '## Queue (in order)\n- gamma own item\n\nCarries open items of: d.md\n' > "$TMP/c.md"
printf '## Queue (in order)\n- alpha own item\n\nCarries open items of: b.md\nCarries open items of: c.md\n' > "$TMP/a.md"
printf '## Queue (in order)\n- alpha own item\n- beta own item\n- gamma own item\n\nCarries open items of: a.md\n' > "$TMP/a2.md"
check "a file carrying two siblings keeps the shared item one sibling closed and the other carries" "- omega shared item" \
  "$(carry "$TMP/a.md" "$TMP/a2.md")"
# One reason pasted on many close lines closes none of them, also when the items it closes came by separate references:
# checked per reference, each branch saw the reason once, and both items were dropped.
mkdir "$TMP/split"
printf '## Queue (in order)\n- alpha export\n' > "$TMP/split/b.md"
printf '## Queue (in order)\n- beta warmup\n' > "$TMP/split/c.md"
printf '## Queue (in order)\n- own item\n\n## Closed since last checkpoint\n- alpha export -- done\n- beta warmup -- done\n\nCarries open items of: b.md\nCarries open items of: c.md\n' > "$TMP/split/a.md"
printf '## Queue (in order)\n- own item\n\nCarries open items of: a.md\n' > "$TMP/split/new.md"
OUT=$(carry "$TMP/split/a.md" "$TMP/split/new.md"); RC=$?
check "one reason on two close lines closes neither of two items from separate references" "1 2" \
  "$RC $(grep -cxE -- '- (alpha export|beta warmup)' <<<"$OUT")"
# r21: each Q-key's title is not part of its reason: "Q-1 alpha export -- done" and "Q-2 beta warmup -- done" give one reason.
printf '## Queue (in order)\n- Q-1 alpha export\n- Q-2 beta warmup\n' > "$TMP/qt.md"
printf '## Queue (in order)\n- none\n\n## Closed since last checkpoint\n- Q-1 alpha export -- done\n- Q-2 beta warmup -- done\n' > "$TMP/qt2.md"
OUT=$(carry "$TMP/qt.md" "$TMP/qt2.md"); RC=$?
check "one reason on two Q-key close lines closes neither, whatever their titles" "1 2" "$RC $(grep -c '^- Q-' <<<"$OUT")"
# The reason is only the text after the line's last " -- ": a reworded title does not make two reasons, a line without
# " -- " gives none, and an item copied with its own status tail gives none.
printf '## Queue (in order)\n- Q-1 alpha export\n- Q-2 beta warmup\n- Q-4 cache warmup\n- zeta plan -- still open: waits on ops\n' > "$TMP/qr.md"
printf '## Queue (in order)\n- none\n\n## Closed since last checkpoint\n- Q-1 alpha exports -- done\n- Q-2 the beta warm-up -- done\n- Q-4 merged with unit omega\n- zeta plan -- still open: waits on ops\n' > "$TMP/qr2.md"
OUT=$(carry "$TMP/qr.md" "$TMP/qr2.md"); RC=$?
check "reworded titles, a line without ' -- ' and a copied status tail close nothing" "1 4" "$RC $(grep -c '^- ' <<<"$OUT")"
printf '## Queue (in order)\n- none\n\n## Closed since last checkpoint\n- Q-1 alpha exports -- shipped in unit alpha\n- Q-2 -- dropped by the owner\n- Q-4 cache warmup -- merged with unit omega\n- zeta plan -- still open: waits on ops -- ops answered, plan done\n' > "$TMP/qr3.md"
check "and each with a reason of its own after its last ' -- ' closes" 0 "$(carry "$TMP/qr.md" "$TMP/qr3.md" >/dev/null; echo $?)"
# r21: a result cut by a cycle depends on where the walk entered it. a carries c then d; c carries b and closes b's item;
# b carries d, d carries b. d's result reused from inside c's branch (b on the path) lost b's item on a's d branch.
mkdir "$TMP/cyc"
printf '## Queue (in order)\n- none\n\nCarries open items of: c.md\nCarries open items of: d.md\n' > "$TMP/cyc/a.md"
printf '## Queue (in order)\n- none\n\n## Closed since last checkpoint\n- ship release -- shipped in c\n\nCarries open items of: b.md\n' > "$TMP/cyc/c.md"
printf '## Queue (in order)\n- ship release\n\nCarries open items of: d.md\n' > "$TMP/cyc/b.md"
printf '## Queue (in order)\n- none\n\nCarries open items of: b.md\n' > "$TMP/cyc/d.md"
printf '## Queue (in order)\n- none\n' > "$TMP/cyc/new.md"
check "an item a cycle partner carries is not lost by the reference order" "1 - ship release" \
  "$(OUT=$(carry "$TMP/cyc/a.md" "$TMP/cyc/new.md"); echo "$? $OUT")"
# The files of a cycle share one result: inside it no file is older, so a member's closure ends only what the cycle
# inherits from outside it (o's item), never another member's own item (x's).
mkdir "$TMP/scc"
printf '## Queue (in order)\n- outer item\n' > "$TMP/scc/o.md"
printf '## Queue (in order)\n- x item\n\n## Closed since last checkpoint\n- outer item -- shipped in x\n\nCarries open items of: y.md\n' > "$TMP/scc/x.md"
printf '## Queue (in order)\n- none\n\n## Closed since last checkpoint\n- x item -- dropped in y\n\nCarries open items of: x.md\nCarries open items of: o.md\n' > "$TMP/scc/y.md"
printf '## Queue (in order)\n- none\n\nCarries open items of: x.md\n' > "$TMP/scc/a.md"
check "a cycle member's closure ends the cycle's outside inheritance, never a member's own item" "1 - x item" \
  "$(OUT=$(carry "$TMP/scc/a.md" "$TMP/cyc/new.md"); echo "$? $OUT")"
# The walk reads each file once, whatever the graph's shape, at every depth. Each gK carries g(K+1) and g(K+2), so a
# file is reached by paths of unequal length; a cache keyed by remaining depth missed every time (196,442 reads at 25
# files). With a back-edge to g1 the whole chain is one cycle. In the dense shape each file carries every other one:
# a path walk that did not reuse a cycle-cut result timed out there (pass 23).
OUT=$(timeout 60 python3 - "$REAL/scripts/checkpoint-context.py" "$TMP/fan" <<'EOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("cc", sys.argv[1]); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
reads, orig = [0], cc.read
cc.read = lambda p: (reads.__setitem__(0, reads[0] + 1), orig(p))[1]
out = []
for cycle in (False, True, "dense"):
    for n in ((11, 22) if cycle == "dense" else (30, 60)):
        d = f"{sys.argv[2]}{n}{cycle}"; os.makedirs(d)
        for g in range(1, n + 1):
            to = [h for h in range(1, n + 1) if h != g] if cycle == "dense" else [h for h in (g + 1, g + 2) if h <= n] + ([1] if cycle and g == n else [])
            rs = "".join(f"Carries open items of: g{h}.md\n" for h in to)
            open(f"{d}/g{g}.md", "w").write(f"## Queue (in order)\n- g{g} item\n\n{rs}")
        for depth in (sys.maxsize, cc.MAX_DEPTH):
            reads[0] = 0
            got = cc.effective(f"{d}/g1.md", depth)
            # gK is (K - 1) / 2 references from g1, rounded up, so carry's ten generations hold g1..g19; dense: one from g1.
            assert len(got) == (n if depth > n or cycle == "dense" else cc.MAX_DEPTH * 2 - 1), (n, cycle, depth, len(got))
            out.append("ok" if reads[0] <= n else f"{n} {cycle} {depth}: {reads[0]} reads")
print(" ".join(out))
EOF
)
check "one read per file on a two-next-files chain, with and without a cycle, and on a dense cycle, at both depths" "ok ok ok ok ok ok ok ok ok ok ok ok" "$OUT"
OUT=$(timeout 20 python3 "$REAL/scripts/checkpoint-context.py" aged "$TMP/fan30False/g1.md" 2>&1); RC=$?
check "aged on Sol's 30-file two-next-files chain exits 0 in time and lists g20 to g30 once each" "0 11" \
  "$RC $(grep -c '^- g[0-9]* item -- carried unseen: [0-9]*$' <<<"$OUT")"
# Pass 23: eleven files, each carrying every other one, is one cycle past the ten-generation depth; a walk that
# re-walks each cycle-cut result per path timed out at 20 s after 405,202 reads. Every file is one reference from
# g0, so nothing ages out.
mkdir -p "$TMP/dense"
for g in $(seq 0 10); do
  { printf '## Queue (in order)\n- g%s item\n\n' "$g"
    for h in $(seq 0 10); do [ "$h" = "$g" ] || printf 'Carries open items of: g%s.md\n' "$h"; done; } > "$TMP/dense/g$g.md"
done
OUT=$(timeout 20 python3 "$REAL/scripts/checkpoint-context.py" aged "$TMP/dense/g0.md" 2>&1); RC=$?
check "aged on eleven files that each carry every other one exits 0 in time and lists nothing" "0 " "$RC $OUT"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

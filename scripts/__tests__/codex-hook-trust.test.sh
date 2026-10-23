#!/usr/bin/env bash
# codex-hook-trust.py runs before every Codex launch (issue 315), so two launches can rewrite one config.toml at
# once. A run that reads the file while another has it truncated writes back only its trust entries, and every
# other Codex setting (the model, providers) is lost. The writer B here is held, by a stand-in for open(), on the
# moment writer A has opened the file to write; the case passes only when B still reads the whole file.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

printf 'model = "deployed-model"\n' > "$T/config.toml"
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "/opt/other/start.sh"}]}]}}\n' > "$T/hooks.json"
python3 - "$SOURCE/scripts/codex-hook-trust.py" "$T" > "$T/race.out" 2>&1 <<'EOF'
import io, runpy, sys, threading
from pathlib import Path
trust = runpy.run_path(sys.argv[1])["trust_home"]
home = sys.argv[2]
config = Path(home) / "config.toml"
truncated, read_done, finished = threading.Event(), threading.Event(), threading.Event()
errors = []

def held_open(path, mode="r", *a, **k):
    stream = open(path, mode, *a, **k)
    if Path(path) == config:
        if mode == "w" and threading.current_thread().name == "A":
            truncated.set()
            read_done.wait(3)
        elif mode == "r" and threading.current_thread().name == "B":
            snapshot = stream.read()
            stream.close()
            read_done.set()
            finished.wait(5)
            return io.StringIO(snapshot)
    return stream

trust.__globals__["open"] = held_open

def launch():
    try:
        trust(home, "", True)
    except BaseException as e:
        errors.append(e)
    finally:
        if threading.current_thread().name == "A":
            finished.set()

a = threading.Thread(target=launch, name="A")
b = threading.Thread(target=launch, name="B")
a.start(); truncated.wait(3); b.start(); a.join(10); b.join(10)
print("errors:", errors)
EOF
check "two launches at once raise nothing" "errors: []" "$(tail -1 "$T/race.out")"
check "and keep the owner's other Codex settings" 1 "$(grep -c '^model = "deployed-model"$' "$T/config.toml")"
check "and trust the hook once" 1 "$(grep -c '^trusted_hash = "sha256:' "$T/config.toml")"

# The lock follows the file written, not the home named: two homes whose config.toml resolve to one file
# (each way a link can get there) read it at once, and the run that writes second must not drop the first
# run's entry. Each reader is held after its read until the other has read too, or a second has passed.
python3 - "$SOURCE/scripts/codex-hook-trust.py" "$T/shapes" > "$T/shapes.out" 2>&1 <<'EOF'
import io, json, os, runpy, sys, threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
trust = runpy.run_path(sys.argv[1])["trust_home"]
real_open = open

def shape(root, links):
    """links: home -> where its config.toml points, relative to root; None is a real file."""
    for home, to in links.items():
        (root / home).mkdir(parents=True, exist_ok=True)
        (root / home / "hooks.json").write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "/opt/start.sh"}]}]}}))
        if to is None:
            (root / home / "config.toml").write_text('model = "deployed"\n')
    for home, to in links.items():
        if to is not None:
            (root / home / "config.toml").symlink_to(root / to)

shapes = {
    "two homes, one file elsewhere": {"shared": None, "a": "shared/config.toml", "b": "shared/config.toml"},
    "one home links into the other": {"b": None, "a": "b/config.toml"},
    "a chain of links": {"shared": None, "link": "shared/config.toml", "a": "link/config.toml", "b": "shared/config.toml"},
}
for name, links in shapes.items():
    root = Path(sys.argv[2]) / name.replace(" ", "-").replace(",", "")
    shape(root, links)
    homes = [root / "a", root / "b"]
    barrier = threading.Barrier(2)

    def held_open(path, mode="r", *a, **k):
        stream = real_open(path, mode, *a, **k)
        if Path(path).name == "config.toml" and mode == "r":
            snapshot = stream.read()
            stream.close()
            try:
                barrier.wait(timeout=1)
            except threading.BrokenBarrierError:
                pass
            return io.StringIO(snapshot)
        return stream

    trust.__globals__["open"] = held_open
    with ThreadPoolExecutor(2) as pool:
        list(pool.map(lambda home: trust(str(home), "", True), homes))
    result = Path(os.path.realpath(homes[0] / "config.toml")).read_text()
    kept = all(f'"{h}/hooks.json:session_start:0:0"' in result for h in homes) and 'model = "deployed"' in result
    print(f"{name}: {'kept' if kept else 'lost'}")
EOF
for s in "two homes, one file elsewhere" "one home links into the other" "a chain of links"; do
  check "shared config ($s): both homes' trust kept" "$s: kept" "$(grep -F "$s:" "$T/shapes.out" || tail -3 "$T/shapes.out")"
done

# A link repointed while a run waits for the old file's lock: the run takes the new file's lock before it writes.
mkdir -p "$T/old" "$T/new" "$T/moved"
printf 'model = "old"\n' > "$T/old/config.toml"; printf 'model = "new"\n' > "$T/new/config.toml"
cp "$T/hooks.json" "$T/moved/hooks.json"; ln -s "$T/old/config.toml" "$T/moved/config.toml"
exec 7<"$T/old"; flock 7
python3 "$SOURCE/scripts/codex-hook-trust.py" --all "$T/moved" >/dev/null 2>&1 7<&- & P=$!
sleep 1; ln -sfn "$T/new/config.toml" "$T/moved/config.toml"
exec 6<"$T/new"; flock 6; exec 7<&-
sleep 1
check "repointed link: the run waits for the new file's lock" 0 "$(grep -c '^trusted_hash = ' "$T/new/config.toml")"
exec 6<&-; wait "$P"
check "repointed link: and then trusts the hook in the new file, the old one untouched" "1:0" "$(grep -c '^trusted_hash = ' "$T/new/config.toml"):$(grep -c '^trusted_hash = ' "$T/old/config.toml")"

# Sol r3: the link repointed after the run has read the old file, under the old folder's lock. The write must
# not carry the old file's settings into the new file, and the new file must still end up trusted.
mkdir -p "$T/old2" "$T/new2" "$T/moved2"
printf 'model = "old"\n' > "$T/old2/config.toml"; printf 'model = "new"\n' > "$T/new2/config.toml"
cp "$T/hooks.json" "$T/moved2/hooks.json"; ln -s "$T/old2/config.toml" "$T/moved2/config.toml"
python3 - "$SOURCE/scripts/codex-hook-trust.py" "$T/moved2" "$T/new2/config.toml" > "$T/after-read.out" 2>&1 <<'EOF'
import io, os, runpy, sys
from pathlib import Path
trust = runpy.run_path(sys.argv[1])["trust_home"]
home, new = sys.argv[2], sys.argv[3]
real_open, moved = open, []

def held_open(path, mode="r", *a, **k):
    stream = real_open(path, mode, *a, **k)
    if Path(path).name == "config.toml" and mode == "r" and not moved:
        snapshot = stream.read()
        stream.close()
        os.remove(os.path.join(home, "config.toml")); os.symlink(new, os.path.join(home, "config.toml"))
        moved.append(1)
        return io.StringIO(snapshot)
    return stream

trust.__globals__["open"] = held_open
trust(home, "", True)
EOF
check "repointed after the read: the new file keeps its own settings" "1:0" "$(grep -c '^model = "new"$' "$T/new2/config.toml"):$(grep -c '^model = "old"$' "$T/new2/config.toml")"
check "repointed after the read: and the new file is trusted" 1 "$(grep -c '^trusted_hash = ' "$T/new2/config.toml")"

# Sol r4, and the rest of its class: config.toml is not the file it was at the
# read (a link now, another file, or edited in place). The run writes nothing over it; a link is retried at its target.
changed() {  # changed <home> <how>: run once, <how> applied to the home's config.toml right after the read
  python3 - "$SOURCE/scripts/codex-hook-trust.py" "$1" "$2" "$T" <<'EOF'
import io, os, runpy, sys
from pathlib import Path
trust = runpy.run_path(sys.argv[1])["trust_home"]
home, how, tmp = sys.argv[2], sys.argv[3], sys.argv[4]
config, real_open, moved = os.path.join(home, "config.toml"), open, []

def held_open(path, mode="r", *a, **k):
    stream = real_open(path, mode, *a, **k)
    if Path(path).name == "config.toml" and mode == "r" and not moved:
        snapshot = stream.read()
        stream.close()
        if how == "link":
            os.remove(config); os.symlink(os.path.join(tmp, "new5.toml"), config)
        elif how == "file":
            real_open(config + ".x", "w").write('model = "theirs"\n'); os.replace(config + ".x", config)
        else:
            real_open(config, "a").write('theirs = 1\n')
        moved.append(1)
        return io.StringIO(snapshot)
    return stream

trust.__globals__["open"] = held_open
print(trust(home, "", True))
EOF
}
for how in link file edit; do
  mkdir -p "$T/h5$how"; cp "$T/hooks.json" "$T/h5$how/hooks.json"; printf 'model = "old"\n' > "$T/h5$how/config.toml"
done
printf 'model = "new"\n' > "$T/new5.toml"
changed "$T/h5link" link > /dev/null 2>&1
check "file made a link after the read: the link is kept, its target keeps its settings and is trusted" "yes:1:1" \
  "$([ -L "$T/h5link/config.toml" ] && echo yes):$(grep -c '^model = "new"$' "$T/new5.toml"):$(grep -c '^trusted_hash = ' "$T/new5.toml")"
OUT=$(changed "$T/h5file" file 2>&1)
check "file replaced after the read: the new file is left as it is, and the run says so" "1:0:1" \
  "$(grep -c '^model = "theirs"$' "$T/h5file/config.toml"):$(grep -c '^trusted_hash = ' "$T/h5file/config.toml"):$(grep -c 'changed since it was read; nothing was written' <<<"$OUT")"
OUT=$(changed "$T/h5edit" edit 2>&1)
check "file edited after the read: the edit is kept, and the run says so" "1:0:1" \
  "$(grep -c '^theirs = 1$' "$T/h5edit/config.toml"):$(grep -c '^trusted_hash = ' "$T/h5edit/config.toml"):$(grep -c 'changed since it was read; nothing was written' <<<"$OUT")"

# Two runs (ticks) with one piece of the first run's state taken away between them: the second run reads no state
# the first left, so it trusts the file the home resolves to now, whichever piece is gone, and keeps its settings.
mkdir -p "$T/tick" "$T/tick-a"; cp "$T/hooks.json" "$T/tick/hooks.json"
printf 'model = "a"\n' > "$T/tick-a/config.toml"; ln -s "$T/tick-a/config.toml" "$T/tick/config.toml"
tick() { python3 "$SOURCE/scripts/codex-hook-trust.py" --all "$T/tick" >/dev/null 2>&1; }
tick
for gone in "the trust block" "the link's target, swapped for a fresh file" "the old target, the link replaced by a file"; do
  case $gone in
    "the trust block") sed -i.bak '/^\[hooks\.state\./d; /^trusted_hash = /d' "$T/tick-a/config.toml" ;;
    "the link's target"*) mkdir -p "$T/tick-b"; printf 'model = "b"\n' > "$T/tick-b/config.toml"; ln -sfn "$T/tick-b/config.toml" "$T/tick/config.toml" ;;
    *) rm "$T/tick-b/config.toml" "$T/tick/config.toml"; printf 'model = "c"\n' > "$T/tick/config.toml" ;;
  esac
  tick
  f=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$T/tick/config.toml")
  check "ticks: $gone gone, the next run trusts the file the home names, its settings kept" "1:1" \
    "$(grep -c '^trusted_hash = ' "$f"):$(grep -c '^model = ' "$f")"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

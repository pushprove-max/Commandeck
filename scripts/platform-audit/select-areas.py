"""Print the areas file's rows to audit, each with its Standards cell from the paved-road registry appended.

Usage: select-areas.py <paved-road-areas.tsv> <paved-road.md> [<changed-files>]
The changed files are NUL-separated, as `git diff --name-only -z` writes them. With no list, every area. A path entry is a prefix, optionally followed by keywords in parentheses
("src/services (billing, credit)"): a changed file under the prefix whose rest names a keyword. A prefix with no
slash ("package.json") also matches that name anywhere in the tree. A changed file under a top folder some area
names, that no area matches, is an error.
"""
import re
import sys

slices, registry = sys.argv[1:3]
changed = [f for f in open(sys.argv[3]).read().split('\0') if f] if len(sys.argv) > 3 else None

standards = {}
for line in open(registry):
    cells = [c.strip() for c in line.strip().strip('|').split('|')]
    if len(cells) == 3 and re.fullmatch(r'\d\d-[a-z0-9-]+', cells[0]):
        standards[cells[0]] = cells[1]


def norm(s):
    return re.sub(r'[\s_*-]', '', s.lower())


def base_of(entry):
    return entry.strip().partition('(')[0].split()[0]


def hit(entry, path):
    base, keywords = base_of(entry), entry.partition('(')[2]
    if path.startswith(base):
        at = 0
    elif '/' not in base and '/' + base in path:
        at = path.index('/' + base) + 1
    else:
        return False
    words = [norm(w) for w in keywords.rstrip(')').split(',') if w.strip()]
    rest = norm(path[at + len(base):])
    return not words or any(w in rest for w in words)


rows = []
for row in open(slices):
    row = row.rstrip('\r\n')
    if not row.strip():
        continue
    area, desc, paths = row.split('\t')
    if not standards.get(area):
        sys.exit(f'select-areas: {area} has no Standards row in {registry}')
    rows.append((area, desc, paths, re.findall(r'[^,(]+(?:\([^)]*\))?', paths)))
# One id is one set of output files: a second row would overwrite the first's.
dup = sorted({r[0] for r in rows if [x[0] for x in rows].count(r[0]) > 1})
if dup:
    sys.exit(f'select-areas: {slices} names an area more than once: {" ".join(dup)}')
if not rows:
    sys.exit(f'select-areas: no area in {slices}; add one line per area of {registry}')
extra = sorted(set(standards) - {r[0] for r in rows})
if extra:
    sys.exit(f'select-areas: {registry} rows with no area in {slices}: {" ".join(extra)}')
# The audited folders are the top folders the areas name. A changed file there in no area (a new folder) would go
# unaudited without a word, so it stops the selection instead.
roots = tuple({base_of(e).split('/')[0] + '/' for r in rows for e in r[3]})
lost = [f for f in changed or [] if f.startswith(roots) and not any(hit(e, f) for r in rows for e in r[3])]
if lost:
    sys.exit(f'select-areas: changed files in no area of {slices}; add their paths to an area: {" ".join(lost)}')
for area, desc, paths, entries in rows:
    if changed is None or any(hit(e, f) for e in entries for f in changed):
        print('\t'.join([area, desc, paths, standards[area]]))

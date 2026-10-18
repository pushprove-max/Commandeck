#!/usr/bin/env python3
"""One command for the computed build review page: collect, render, file, open in Orca.

No model is involved. It runs only when the owner asks for a build review, never at a merge (the owner, 2026-10-14):
  review.py <worktree path> [--out-dir DIR] [--open-in WORKTREE] [--no-open] [--main DIR]
            [collect.py options such as --max-review-min 30 --max-test-share 0.33 --max-usd 30]

The page is written to DIR/<date>/<project>/<unit>-review.html (default DIR ~/.commandeck/reviews) and,
with --open-in, opened as a browser tab in that worktree. Every step after collect is best effort.
A worktree already removed is placed by --main, the project's main checkout; without it the review is refused.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))


def orca(*args):
    exe = shutil.which('orca-ide')
    if not exe:
        return None
    return subprocess.run([exe, *args, '--json'], capture_output=True, text=True, timeout=30)


def main_checkout(worktree):
    """The main checkout the worktree belongs to: its folder names the project."""
    common = subprocess.run(['git', '-C', worktree, 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                            capture_output=True, text=True).stdout.strip()
    return common[:-len('/.git')] if common.endswith('/.git') else common


def places(worktree, main=None):
    """(work folder, page path stem): a folder per project, so two projects' units never share a name.

    The project is the worktree's main checkout; once the worktree is removed only --main (the checkout) can name it."""
    wt = worktree.rstrip('/')
    home = main_checkout(wt if os.path.isdir(wt) else main) if os.path.isdir(wt) or main else ''
    if not home:
        raise SystemExit(f'review.py: {wt} is not a worktree any more, so its project is unknown; pass --main <the project\'s main checkout>')
    project, unit = os.path.basename(home), os.path.basename(wt)
    return f'/tmp/commandeck/worktreereview/{project}/{unit}', f'{project}/{unit}'


def rungs(wt, unit):
    """One row per numbered batch item of the brief, with the rung its evidence line records.

    The brief's own `[rung N]` is the plan, not what was built, so it is never read as the rung:
    an item with no `Ponytail: item <n>: rung <N>; lazier option: ...` line has rung None.
    """
    def text(name):
        try:
            return open(os.path.join(wt, '.claude', 'briefs', name), errors='replace').read()
        except OSError:
            return ''
    said = {int(n): (rung, why.strip().rstrip('`').strip())
            for n, rung, why in re.findall(r'^[-\s`]*Ponytail: item (\d+): rung (\d+); lazier option: (.+)$', text(f'{unit}-evidence.md'), re.M)}
    items = re.findall(r'^\s*(\d+)\. (?:\[rung \d+\] )?(#\d+)', text(f'{unit}.md'), re.M)
    return [{'item': int(n), 'issue': issue, 'rung': said.get(int(n), (None, None))[0], 'lazier': said.get(int(n), (None, None))[1]}
            for n, issue in items]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('worktree')
    ap.add_argument('--out-dir', default=os.path.expanduser('~/.commandeck/reviews'))
    ap.add_argument('--open-in')
    ap.add_argument('--no-open', action='store_true')
    ap.add_argument('--main')
    a, passthrough = ap.parse_known_args()
    wt = a.worktree.rstrip('/')
    unit = os.path.basename(wt)
    work, name = places(wt, a.main)
    done = subprocess.run([sys.executable, f'{HERE}/collect.py', wt, '--out', work, *passthrough, *(['--main', a.main] if a.main else [])])
    if done.returncode:
        return done.returncode
    result = json.load(open(f'{work}/result.json'))
    result['rungs'] = rungs(wt, unit)
    json.dump(result, open(f'{work}/result.json', 'w'), indent=1)
    day = os.path.join(a.out_dir, datetime.fromtimestamp(result['end']).strftime('%Y-%m-%d'))
    page = os.path.join(day, f'{name}-review.html')
    os.makedirs(os.path.dirname(page), exist_ok=True)
    subprocess.run([sys.executable, f'{HERE}/render.py', f'{work}/result.json', page], check=True)
    shutil.copy(f'{work}/result.json', os.path.join(day, f'{name}-review.json'))
    print('page:', page)
    try:
        if a.open_in and not a.no_open:
            opened = orca('tab', 'create', '--url', 'file://' + page, '--worktree', 'path:' + a.open_in)
            print('opened in Orca:', bool(opened and opened.returncode == 0))
    except (OSError, subprocess.SubprocessError) as e:
        print('page written; Orca step failed:', e)
    print('flags:', result.get('flags') or 'none')
    return 0


if __name__ == '__main__':
    sys.exit(main())

"""Which folders are a unit's: its worktree and the scratch copy a fresh closing review pass runs in.

The one home of the copy's path: every reader that ties a session to a unit by its folder asks `belongs`, and no
other code file spells the copy's folder name (unit-folders.test.sh checks that).
`belongs` reads only the two path strings and their realpaths, so its answer is the same whether the worktree, the
copy or a seat record still exists, and whenever the session's folder was recorded.
Standard library only.
"""
import os
import subprocess

COPIES = "closing-copy"


def scratch():
    """PP_SCRATCH, else COMMANDECK_SCRATCH, else what paths.sh names; raises when none gives one, so a reader fails loud."""
    s = os.environ.get("PP_SCRATCH") or os.environ.get("COMMANDECK_SCRATCH")
    if not s:
        here = os.path.dirname(os.path.abspath(__file__))
        s = subprocess.run(["bash", "-c", '. "$1/paths.sh" >/dev/null 2>&1 && printf %s "$PP_SCRATCH"', "_", here],
                           capture_output=True, text=True).stdout
    if not s:
        raise RuntimeError("unit_folders: no scratch folder (PP_SCRATCH unset and paths.sh named none)")
    return s


def closing_root():
    return os.path.join(scratch(), COPIES)


def copy(wt):
    return os.path.join(closing_root(), os.path.basename(wt.rstrip("/")))


def _within(path, root):
    root = root.rstrip("/")
    return path == root or path.startswith(root + "/")


def belongs(cwd, wt):
    """Whether a session run in `cwd` is the unit's whose worktree is `wt`: the worktree, its copy, or a folder under either."""
    if not isinstance(cwd, str) or not cwd or not wt:
        return False
    homes = (wt, copy(wt))
    return any(_within(cwd, h) for h in homes) or any(_within(os.path.realpath(cwd), os.path.realpath(h)) for h in homes)


if __name__ == "__main__":
    import sys
    if sys.argv[1:2] == ["copy"] and len(sys.argv) == 3:
        print(copy(sys.argv[2]))
    elif sys.argv[1:] == ["root"]:
        print(closing_root())
    else:
        sys.exit("usage: unit_folders.py copy <worktree> | root")

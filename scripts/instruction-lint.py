#!/usr/bin/env python3
"""instruction-lint.py [--repo DIR] [--memory-dir DIR] [--global FILE] [--active-index]

Deterministic first pass over a project's instruction files, for the doctor.
Prints one `file:line kind detail` row per flag and exits 1 when it flags
anything.

Kinds:
  duplicate-subject  one subject (`**Subject.**` lead or `##` heading) in two places
  stale-model        a pinned model id; routing names families, never versions
  open-conflict      an "OPEN conflict" marker
  orphan-memory      a memory file named neither in MEMORY.md nor in a file MEMORY.md names
  dead-index         a MEMORY.md link to a missing file
  superseded-memory  a memory whose description says SUPERSEDED: its name still states the old rule
  over-200-lines     CLAUDE.md, a rules file with no `paths:` frontmatter, or the global CLAUDE.md past 200
                     lines: it loads in every session and is followed less well the longer it is
                     (AGENT_STARTUP.md and main-session.md are left out: startup-size.sh holds them)
  memory-over-limit  MEMORY.md past 200 lines or 25 KB: what is past that is not loaded
  unknown-option     `--option <key>=` in an instruction file, template, brief, doc or hook with a key that is
                     not a userConfig key of .claude-plugin/plugin.json
  retired-name       a name listed in config/retired.tsv, with what replaced it
  dead-ref           a gone reference, outside fenced lines: a backticked path under templates/, docs/, scripts/,
                     hooks/, .claude/rules/ or another top-level directory git tracks, a backticked script name no tracked
                     file has, or a Markdown link target that is not on disk

Every row ends with `rule: <file>#<heading>`, where the rule is written down.

--active-index does not lint: it keeps MEMORY.md, the index Claude Code loads at every start, to the active memories.
A memory whose frontmatter says `status: archived` has its index line moved to MEMORY-archive.md in the same folder
(one pointer line stays in MEMORY.md, so orphan-memory still reaches the file); a line whose memory is active again
moves back. It writes only when something moves.

Limit: a mechanical first pass. duplicate-subject matches only an identical bold
lead or heading, so two rules that disagree under different wording or headings
are never flagged; a reader finds those.
"""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path

MODEL_ID = re.compile(r"\b(claude-(?:opus|sonnet|haiku|fable)-\d+(?:-\d+)*|gpt-\d+(?:\.\d+)*(?:-[a-z]+)?)\b")
BOLD_LEAD = re.compile(r"^\s*(?:[-*]\s+|\d+\.\s+)?\*\*(.+?)\*\*")
HEADING = re.compile(r"^#{2,4}\s+(.+)")
OPEN_CONFLICT = re.compile(r"\bOPEN conflict\b", re.IGNORECASE)
# The fence rule of fence.sh: backticks or tildes, indented or not, closed by the same character at least as long.
FENCE = re.compile(r"\s*(`{3,}|~{3,})(.*)")
INDEX_LINK = re.compile(r"\]\(([^)\s]+\.md)\)")
MD_NAME = re.compile(r"[\w.-]+\.md")
PATHS = re.compile(r"^paths:", re.MULTILINE)
MAX_LINES, MAX_MEMORY_BYTES = 200, 25_600
ARCHIVE, ARCHIVE_POINTER = "MEMORY-archive.md", "- [Archived memories](MEMORY-archive.md): not loaded at start"
ARCHIVED = re.compile(r"^status:[ \t]*[\"']?archived[\"']?[ \t]*$", re.MULTILINE)
# A profile's own folder (Orca), else the home one: the folder Claude Code reads memory and CLAUDE.md from.
CONFIG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
PLUGIN_ROOT = Path(__file__).resolve().parent.parent
RULE = "docs/commands.md#rules-audit"
# shortcut: only the --option form; a bare backticked key (`wakeKinds`) is not told from any other code word. Upgrade when an old key slips through.
OPTION_USE = re.compile(r"--option[ =]([A-Za-z]\w*)=")
KNOWN_TOPS = {"templates", "docs", "scripts", "hooks"}
BACKTICK = re.compile(r"`([^`]+)`")
MD_LINK = re.compile(r"\]\(([^)\s]+)\)")
SCRIPT_NAME = re.compile(r"[\w.-]+\.(?:sh|py)")
NOT_A_PATH = re.compile(r"[<>*{}$\[\]|]|\.\.\.")


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


def repo_files(repo):
    names = ["CLAUDE.md", "AGENT_STARTUP.md", ".claude/main-session.md"]
    found = [repo / n for n in names]
    found += sorted((repo / ".claude/rules").glob("*.md"))
    return [p for p in found if p.is_file()]


def text_files(repo):
    # Where rules and commands are written down, beyond the always-loaded files; CHANGELOG.md never.
    # Tests are left out: their fixtures name paths and options that do not exist, on purpose.
    globs = ["templates/**/*.md", ".claude/briefs/*.md", "docs/**/*.md", "hooks/**/*.sh"]
    return sorted(p for g in globs for p in repo.glob(g) if p.is_file() and "__tests__" not in p.parts)


def retired():
    path = PLUGIN_ROOT / "config/retired.tsv"
    rows = [l.split("\t", 1) for l in path.read_text().splitlines() if l.strip() and not l.startswith("#")] if path.is_file() else []
    return [(r[0], r[1] if len(r) > 1 else "") for r in rows]


def subject(line):
    heading = HEADING.match(line)
    m = heading or BOLD_LEAD.match(line)
    if not m:
        return None
    s = re.sub(r"\([^)]*\)", "", m.group(1)).lower()
    s = " ".join(re.sub(r"[^a-z0-9 /-]", " ", s).split())
    # A one-word bold lead ("**Why:**") is a label, not a subject; a heading is always a subject.
    return s if s and (heading or len(s.split()) >= 2) else None


def frontmatter(text):
    # Line 1 `---` to the first later `---` line, nothing between included; no closing line is no frontmatter.
    # A body that shows a field, then a `---` rule, says nothing about the file.
    lines = text.splitlines()
    if lines[:1] != ["---"] or "---" not in lines[1:]:
        return ""
    return "".join(l + "\n" for l in lines[1 : lines.index("---", 1)])


def default_memory_dir(repo):
    # Claude Code names the folder by the path with every character that is not a letter or a digit a dash.
    common = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    main = common[: -len("/.git")] if common.endswith("/.git") else common
    return CONFIG_DIR / "projects" / re.sub(r"[^A-Za-z0-9]", "-", main) / "memory"


def active_index(memory_dir):
    index, archive = memory_dir / "MEMORY.md", memory_dir / ARCHIVE
    if not index.is_file():
        return
    gone = {p.name for p in memory_dir.glob("*.md") if p.name not in ("MEMORY.md", ARCHIVE) and ARCHIVED.search(frontmatter(p.read_text()))}
    old_index = index.read_text().splitlines()
    old_archive = archive.read_text().splitlines() if archive.is_file() else []
    # ./old.md is old.md, as the lint's dead-index check reads it.
    is_gone = lambda line: any(os.path.normpath(t) in gone for t in INDEX_LINK.findall(line)[:1])
    lines = [l for l in old_index if l != ARCHIVE_POINTER]
    # A line in both files is a start stopped between the writes below: it is kept once, in the file it belongs to.
    keep = [l for l in lines if not is_gone(l)] + [l for l in old_archive if not is_gone(l) and l not in lines]
    moved = [l for l in lines if is_gone(l) and l not in old_archive] + [l for l in old_archive if is_gone(l)]
    new_index = keep + ([ARCHIVE_POINTER] if moved else [])
    # A line is written to its new file before it leaves its old one, so a failed or stopped write loses none and the
    # next start finishes the move. MEMORY.md is never removed; an emptied archive is.
    both = old_archive + [l for l in moved if l not in old_archive]
    for path, old, new in ((archive, old_archive, both), (index, old_index, new_index), (archive, both, moved)):
        if new == old:
            continue
        if new or path == index:
            tmp = path.with_name(path.name + ".tmp")
            tmp.write_text("".join(l + "\n" for l in new))
            os.replace(tmp, path)
        else:
            path.unlink()


def git_files(repo):
    ls = subprocess.run(["git", "-C", str(repo), "ls-files"], capture_output=True, text=True)
    return ls.stdout.splitlines() if ls.returncode == 0 else []


def dead_refs(repo, path, line, tracked):
    """The gone references on one line: a backticked path under a known top-level directory, a Markdown link target, and
    a backticked script name no tracked file has. With no tracked files only the fixed prefixes are read."""
    tops = KNOWN_TOPS | {t.split("/")[0] for t in tracked if "/" in t} - {".claude"}
    names = {t.rsplit("/", 1)[-1] for t in tracked}
    gone = []
    for span in BACKTICK.findall(line):
        # Inside a shell string a backtick is escaped (\`), and the escape closes the span like a plain backtick; an
        # even run of backslashes before it is literal backslashes, not an escape (#674).
        if (len(span) - len(span.rstrip("\\"))) % 2:
            span = span[:-1]
        token = span.split()[0] if span.split() else ""
        target = re.sub(r"(?::\d+)?(?:#.*)?$", "", token.rstrip(".,;:)"))
        if not target or NOT_A_PATH.search(target) or "://" in target:
            continue
        if "/" in target:
            # Untracked build output is real in a built checkout and absent in a clean one. A doc names the
            # project's own .claude/ files (runtime state, setup output) as often as its own: only .claude/rules/ is read.
            if (target.split("/")[0] in tops or (target.startswith(".claude/rules/") and target != ".claude/rules/")) and not {"node_modules", "dist"} & set(target.split("/")) and not (repo / target).exists():
                gone.append(target)
        elif tracked and SCRIPT_NAME.fullmatch(target) and not target.startswith(".") and target not in names:
            gone.append(target)
    for link in MD_LINK.findall(line if tracked else ""):
        target = link.split("#")[0]
        if target and not NOT_A_PATH.search(target) and "://" not in target and not link.startswith(("mailto:", "/")) and not (path.parent / target).exists():
            gone.append(target)
    return list(dict.fromkeys(gone))


def lint(repo, memory_dir, global_file):
    rows = []
    instruction = [(p, str(p.relative_to(repo))) for p in repo_files(repo)]
    if global_file and global_file.is_file():
        instruction.append((global_file, str(global_file)))
    memory = sorted(memory_dir.glob("*.md")) if memory_dir.is_dir() else []

    # Instruction files only: every memory shares template leads ("**How to apply:**").
    subjects = {}
    for path, shown in instruction:
        for n, line in enumerate(path.read_text().splitlines(), 1):
            s = subject(line)
            if s:
                subjects.setdefault(s, []).append(f"{shown}:{n}")

    for places in subjects.values():
        for here in places if len(places) > 1 else []:
            others = ", ".join(p for p in places if p != here)
            rows.append(f"{here} duplicate-subject also at {others}")

    # Loaded in every session; a rules file with `paths:` loads only when a matching file is read.
    for path, shown in instruction:
        if shown in ("AGENT_STARTUP.md", ".claude/main-session.md") or PATHS.search(frontmatter(path.read_text())):
            continue
        count = len(path.read_text().splitlines())
        if count > MAX_LINES:
            rows.append(f"{shown}:{MAX_LINES + 1} over-200-lines {count} lines")

    for path, shown in instruction + [(p, str(p)) for p in memory]:
        for n, line in enumerate(path.read_text().splitlines(), 1):
            for model in sorted(set(MODEL_ID.findall(line))):
                rows.append(f"{shown}:{n} stale-model {model}")
            if OPEN_CONFLICT.search(line):
                rows.append(f"{shown}:{n} open-conflict")

    index = memory_dir / "MEMORY.md"
    if index.is_file():
        text = index.read_text()
        if len(text.splitlines()) > MAX_LINES or len(text.encode()) > MAX_MEMORY_BYTES:
            rows.append(f"{index}:1 memory-over-limit {len(text.splitlines())} lines, {len(text.encode())} bytes")
        for n, line in enumerate(text.splitlines(), 1):
            for target in INDEX_LINK.findall(line):
                if not (memory_dir / target).is_file():
                    rows.append(f"{index}:{n} dead-index {target}")
        # A file named by an index-named file is still indexed.
        named = set(MD_NAME.findall(text))
        reachable = named.union(*(MD_NAME.findall(p.read_text()) for p in memory if p.name in named))
        for path in memory:
            if path != index and path.name not in reachable:
                rows.append(f"{path}:1 orphan-memory")
    else:
        rows.extend(f"{path}:1 orphan-memory" for path in memory)
    for path in memory:
        for n, line in enumerate(frontmatter(path.read_text()).splitlines(), 2):
            if re.match(r"description:\s*\"?SUPERSEDED", line):
                rows.append(f"{path}:{n} superseded-memory")

    # Rules and commands live in more files than the always-loaded ones: these three kinds read them all.
    known = set(json.loads((PLUGIN_ROOT / ".claude-plugin/plugin.json").read_text()).get("userConfig", {}))
    names = retired()
    tracked = git_files(repo)
    seen = {p for p, _ in instruction}
    for path, shown in instruction + [(p, str(p.relative_to(repo))) for p in text_files(repo) if p not in seen]:
        fence = ""
        for n, line in enumerate(path.read_text().splitlines(), 1):
            for m in OPTION_USE.finditer(line):
                if m.group(1) not in known:
                    rows.append(f"{shown}:{n} unknown-option {m.group(1)}")
            for name, replacement in names:
                if name in line:
                    rows.append(f"{shown}:{n} retired-name {name}" + (f", now: {replacement}" if replacement else ""))
            run = FENCE.match(line)
            if fence:
                if run and run.group(1)[0] == fence[0] and len(run.group(1)) >= len(fence) and not run.group(2).strip():
                    fence = ""
            elif run:
                fence = run.group(1)
            else:
                rows.extend(f"{shown}:{n} dead-ref {ref}" for ref in dead_refs(repo, path, line, tracked))
    return [f"{row} rule: {RULE}" for row in rows]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", type=Path)
    ap.add_argument("--memory-dir", type=Path)
    ap.add_argument("--active-index", action="store_true")
    ap.add_argument("--global", dest="global_file", type=Path, default=CONFIG_DIR / "CLAUDE.md")
    args = ap.parse_args()
    repo = args.repo or Path(git(".", "rev-parse", "--show-toplevel"))
    memory_dir = args.memory_dir or default_memory_dir(repo)
    if args.active_index:
        active_index(memory_dir)
        return 0
    rows = lint(repo, memory_dir, args.global_file)
    for row in rows:
        print(row)
    return 1 if rows else 0


if __name__ == "__main__":
    raise SystemExit(main())

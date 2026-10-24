#!/usr/bin/env python3
"""instruction-lint.py [--repo DIR] [--memory-dir DIR] [--global FILE]

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
  dead-ref           a backticked templates/, docs/, scripts/, hooks/ or .claude/rules/ path that is not on disk

Every row ends with `rule: <file>#<heading>`, where the rule is written down.

Limit: a mechanical first pass. duplicate-subject matches only an identical bold
lead or heading, so two rules that disagree under different wording or headings
are never flagged; a reader finds those.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

MODEL_ID = re.compile(r"\b(claude-(?:opus|sonnet|haiku|fable)-\d+(?:-\d+)*|gpt-\d+(?:\.\d+)*(?:-[a-z]+)?)\b")
BOLD_LEAD = re.compile(r"^\s*(?:[-*]\s+|\d+\.\s+)?\*\*(.+?)\*\*")
HEADING = re.compile(r"^#{2,4}\s+(.+)")
OPEN_CONFLICT = re.compile(r"\bOPEN conflict\b", re.IGNORECASE)
INDEX_LINK = re.compile(r"\]\(([^)\s]+\.md)\)")
MD_NAME = re.compile(r"[\w.-]+\.md")
PATHS_FRONTMATTER = re.compile(r"\A---\n(?:.*\n)*?paths:", re.MULTILINE)
MAX_LINES, MAX_MEMORY_BYTES = 200, 25_600
PLUGIN_ROOT = Path(__file__).resolve().parent.parent
RULE = "docs/commands.md#rules-audit"
# shortcut: only the --option form; a bare backticked key (`wakeKinds`) is not told from any other code word. Upgrade when an old key slips through.
OPTION_USE = re.compile(r"--option[ =]([A-Za-z]\w*)=")
REF = re.compile(r"`((?:templates|docs|scripts|hooks|\.claude/rules)/[^`\s]+)`")
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


def default_memory_dir(repo):
    # Claude Code names the folder by the path with every character that is not a letter or a digit a dash.
    common = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    main = common[: -len("/.git")] if common.endswith("/.git") else common
    return Path.home() / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", main) / "memory"


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
        if shown in ("AGENT_STARTUP.md", ".claude/main-session.md") or PATHS_FRONTMATTER.match(path.read_text()):
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
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if re.match(r"description:\s*\"?SUPERSEDED", line):
                rows.append(f"{path}:{n} superseded-memory")

    # Rules and commands live in more files than the always-loaded ones: these three kinds read them all.
    known = set(json.loads((PLUGIN_ROOT / ".claude-plugin/plugin.json").read_text()).get("userConfig", {}))
    names = retired()
    seen = {p for p, _ in instruction}
    for path, shown in instruction + [(p, str(p.relative_to(repo))) for p in text_files(repo) if p not in seen]:
        for n, line in enumerate(path.read_text().splitlines(), 1):
            for m in OPTION_USE.finditer(line):
                if m.group(1) not in known:
                    rows.append(f"{shown}:{n} unknown-option {m.group(1)}")
            for name, replacement in names:
                if name in line:
                    rows.append(f"{shown}:{n} retired-name {name}" + (f", now: {replacement}" if replacement else ""))
            for ref in REF.findall(line):
                ref = re.sub(r"(?::\d+)?(?:#.*)?$", "", ref.rstrip(".,;:)"))
                if not NOT_A_PATH.search(ref) and not (repo / ref).exists():
                    rows.append(f"{shown}:{n} dead-ref {ref}")
    return [f"{row} rule: {RULE}" for row in rows]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", type=Path)
    ap.add_argument("--memory-dir", type=Path)
    ap.add_argument("--global", dest="global_file", type=Path, default=Path.home() / ".claude/CLAUDE.md")
    args = ap.parse_args()
    repo = args.repo or Path(git(".", "rev-parse", "--show-toplevel"))
    rows = lint(repo, args.memory_dir or default_memory_dir(repo), args.global_file)
    for row in rows:
        print(row)
    return 1 if rows else 0


if __name__ == "__main__":
    raise SystemExit(main())

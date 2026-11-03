#!/usr/bin/env bash
# PreToolUse Bash helper: Claude Code loads a path rule only for Read/Edit/Write, so a shell write (redirect,
# heredoc, tee, sed -i, python open) into a rule's `paths:` gets that rule here instead, once per session per rule.
# The rules are the project's own `.claude/rules` (the git top of the payload's cwd). The globs are read from each
# rule's frontmatter, their one home. Never refuses: registered without onFailure.
# Retire when: Claude Code applies .claude/rules globs to Bash writes
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# Most commands carry no write marker: one pattern test, no python start.
case "$CMD" in *'>'*|*tee*|*'-i'*|*perl*|*'<<'*|*'open('*|*write_*|*'cp '*|*'mv '*|*'install '*) ;; *) exit 0 ;; esac
KEY=$(echo "$INPUT" | jq -r '.session_id // empty'); KEY=${KEY:-${CLAUDE_SESSION_ID:-$PPID}}
CWD=$(echo "$INPUT" | jq -r '.cwd // empty'); CWD=${CWD:-$PWD}
# The project is the git top of the cwd; outside a checkout there is no rule.
TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$TOP/.claude/rules" ] || exit 0
. "${BASH_SOURCE[0]%/*}/../scripts/paths.sh" 2>/dev/null || exit 0
mkdir -p "$PP_SCRATCH" 2>/dev/null || exit 0
# Targets come from what bash runs, never from heredoc bodies or quoted prose. Mark mode keeps a quoted one-token
# span (`> "foo.ts"`) as its word.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh"
CODE=$(strip_quoted "$CMD" $'\x01')
# A function, not $(... <<'PY'): Bash 3.2 misreads the quotes of a here-document inside $(...).
rules_py() { python3 -I - "$@" <<'PY' 2>/dev/null
import hashlib, json, os, re, sys
rules_dir, key, cwd, cmd, code, scratch = sys.argv[1:]
# Claude Code saves hook output over 10,000 chars to disk and shows only a
# 2,000-char preview, so an over-cap rule that comes first is not injected.
CAP = 10000
root = os.path.realpath(os.path.join(rules_dir, "..", ".."))

# Write targets: a redirection's word, every tee file, the files of sed/perl -i,
# the last argument of cp/mv/install -- all read from the stripped code.
targets = [t for t in re.findall(r"(?<![<>])>>?\|?\s*([^\s<>|;&()]+)", code) if t != "/dev/null"]
for seg in re.split(r"[;&|()\n]+", code):
    # A quoted span holding a space prints the mark alone; it stays a placeholder
    # word so operand positions hold (`sed -i 's/a b/c/' f` still names f).
    words = [w[1:] if w.startswith("\x01") and len(w) > 1 else w
             for w in re.sub(r"[0-9]*>>?\|?\s*\S+", " ", seg).split()]
    while words and (re.match(r"\w+=", words[0]) or words[0] in ("sudo", "env", "command", "exec")):
        words.pop(0)
    if not words:
        continue
    prog, args = os.path.basename(words[0]), words[1:]
    files = [a for a in args if not a.startswith("-")]
    if prog == "tee":
        targets += files
    elif prog in ("cp", "mv", "install") and files:
        targets.append(files[-1])
    elif prog in ("sed", "perl") and any(re.match(r"-[a-zA-Z]*i|--in-place", a) for a in args):
        # Without -e/-f the first operand is the script, not a file. The script may
        # be attached (`-e's/a/b/'`, `--expression=...`).
        scripted = any(re.match(r"-[a-zA-Z]*[ef]|--(?:expression|file)(?:=|$)", a) for a in args)
        files = [a for i, a in enumerate(args) if not a.startswith("-")
                 and not (i and re.fullmatch(r"-[a-zA-Z]*[ef]", args[i - 1]))]
        targets += files if scripted else files[1:]
# A python open(<path>, 'w'|'a') or Path(<path>).write_* names its own target in
# quotes, so it is read from the raw command.
targets += re.findall(r"""\bopen\(\s*['"]([^'"]+)['"]\s*,\s*['"][wa]""", cmd)
targets += re.findall(r"""\bPath\(\s*['"]([^'"]+)['"]\s*\)\.write_(?:text|bytes)\b""", cmd)
targets = [t for t in targets if t.strip("\x01")]
if not targets:
    sys.exit(0)

def glob_re(glob):
    out, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif glob.startswith("**", i):
            out, i = out + ".*", i + 2
        else:
            out, i = out + {"*": "[^/]*", "?": "[^/]"}.get(glob[i], re.escape(glob[i])), i + 1
    return re.compile(out + r"\Z")

# A `cd` earlier in the command moves where later relative paths land; trying
# every directory the command visits may over-match, never under-match.
dirs = [cwd]
for target in re.findall(r"\bcd\s+([^\s;&|]+)", code):
    dirs.append(os.path.join(dirs[-1], target.lstrip("\x01")))
paths = set()
for token in targets:
    for d in dirs:
        full = os.path.realpath(os.path.join(d, token.lstrip("\x01")))
        if full.startswith(root + os.sep):
            paths.add(os.path.relpath(full, root))

def rule_text(name):
    with open(os.path.join(rules_dir, name)) as f:
        return f.read()

# Rules sort by name; the first that fits the cap goes, the rest ride along when they fit.
names = sorted(n for n in os.listdir(rules_dir) if n.endswith(".md"))
# The mark names the project too: one session writing in two projects sees each project's own same-named rule.
project = hashlib.sha1(os.path.realpath(rules_dir).encode()).hexdigest()[:12]
blocks = []
for name in names:
    marker = os.path.join(scratch, f"bash-rules-{name[:-3]}-{project}-{key}")
    if os.path.exists(marker):
        continue
    text = rule_text(name)
    front = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not front:
        continue
    lines = front.group(1).splitlines()
    globs = []
    for i, line in enumerate(lines):
        if line.startswith("paths:"):
            if line[6:].strip():
                globs = json.loads(line[6:])
            else:
                for item in lines[i + 1:]:
                    if not item.lstrip().startswith("-"):
                        break
                    globs.append(item.strip()[1:].strip().strip("\"'"))
    patterns = [glob_re(g) for g in globs]
    hit = next((p for p in sorted(paths) if any(r.match(p) for r in patterns)), None)
    if not hit:
        continue
    body = text[front.end():].strip()
    msg = (f"This command writes {hit}, which matches .claude/rules/{name}. Shell writes do not load "
           f"path rules, so here it is (once per session):\n\n{body}")
    if not blocks and len(msg) >= CAP:
        msg = (f"This command writes {hit}, which matches .claude/rules/{name}. Shell writes do not load "
               f"path rules and this one is too long to inject: Read .claude/rules/{name} before writing.")
    # The output stays under the cap: a rule that does not fit beside the first waits for the next write.
    if blocks and len("\n\n".join(blocks + [msg])) >= CAP:
        continue
    open(marker, "w").close()
    blocks.append(msg)
if blocks:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "\n\n".join(blocks)}}))
PY
}
OUT=$(rules_py "$TOP/.claude/rules" "$KEY" "$CWD" "$CMD" "$CODE" "$PP_SCRATCH")
[ -n "$OUT" ] && { HOOK_FIRE_ADVISE=1; echo "$OUT"; }
exit 0

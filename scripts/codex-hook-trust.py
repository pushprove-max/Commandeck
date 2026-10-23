#!/usr/bin/env python3
"""Trust the plugin's hooks in a Codex home's hooks.json by writing their hashes to config.toml.

Codex runs a user hook only after it is trusted, and trust is a
`[hooks.state."<hooks.json path>:<event>:<group>:<index>"]` entry in the same
home's config.toml carrying `trusted_hash = "sha256:<hex>"`. The interactive
`/hooks` menu writes that entry; nothing else in the Codex CLI does, and a
Codex pane started by Orca opens on the review menu instead of booting while
an entry is missing. This script computes the same hash Orca computes for its
own hook (verified against Orca's stored value): sha256 over the JSON of
`{event_name, hooks:[{type, command, timeout, async, statusMessage?}],
matcher?}` with keys sorted recursively and no whitespace.

By default only the entries that run the plugin's dispatcher
(templates/codex-hooks.json) are trusted: another tool's hook in the same file
is the owner's to review, and this script never vouches for it. With --all
(the owner's answer to setup's trust-all question) every hook in the file is
trusted: a tool update rewrites its own hook, the new hash is not trusted, and
every Codex pane then opens on the review menu. Launches run it with --all
right before they start Codex. Run it after setup writes the entries and after
a plugin update moves the dispatcher. A hooks.json that is a link
gets entries under both path spellings. Existing entries are left alone; a
changed hook has only its `trusted_hash` line rewritten, so `enabled = false`
and anything else the /hooks menu wrote survives. No backup is made: setup's
install manifest already holds the file as it was before the plugin.

Exits non-zero listing every dispatcher entry it wrote NO trust line for -- an
event or a handler type it does not recognise. Those still need the /hooks
menu, and an untrusted entry opens every Codex pane on the review menu.

    python3 scripts/codex-hook-trust.py            # $CODEX_HOME, else ~/.codex
    python3 scripts/codex-hook-trust.py <home>...  # the homes named
    python3 scripts/codex-hook-trust.py --all [<home>...]     # trust every hook in the home, not only the plugin's
    python3 scripts/codex-hook-trust.py --check [--all] [<home>...]   # write nothing; exit 1 naming each entry not
                                                              # trusted or modified (--all: every hook, not only the plugin's)
    python3 scripts/codex-hook-trust.py --list [--all] [<home>...]    # write nothing; name the hooks a run would trust
    python3 scripts/codex-hook-trust.py --forget [<home>...]  # take the plugin's trust entries out (uninstall runs
                                                              # it BEFORE it removes the hooks: the entries name them)
"""
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import tempfile

EVENTS = {
    "PreToolUse": "pre_tool_use",
    "PermissionRequest": "permission_request",
    "PostToolUse": "post_tool_use",
    "PreCompact": "pre_compact",
    "PostCompact": "post_compact",
    "SessionStart": "session_start",
    "UserPromptSubmit": "user_prompt_submit",
    "SubagentStart": "subagent_start",
    "SubagentStop": "subagent_stop",
    "Stop": "stop",
    "Interrupt": "interrupt",
}
# Events whose matcher does not take part in the hash (Orca's table).
NO_MATCHER = {"user_prompt_submit", "stop"}


def canon(value):
    if isinstance(value, list):
        return [canon(v) for v in value]
    if isinstance(value, dict):
        return {k: canon(value[k]) for k in sorted(value)}
    return value


def hook_hash(event, hook, matcher):
    entry = {
        "type": "command",
        "command": hook["command"],
        "timeout": max(1, hook.get("timeout", 600)),
        "async": hook.get("async", False),
    }
    if "statusMessage" in hook:
        entry["statusMessage"] = hook["statusMessage"]
    definition = {"event_name": event, "hooks": [entry]}
    if matcher is not None and event not in NO_MATCHER:
        definition["matcher"] = matcher
    raw = json.dumps(canon(definition), separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(raw.encode()).hexdigest()


# The plugin's entries START as its template does. An owner's hook that only
# mentions the path is the owner's to review: install-lib.sh IL_OURS_RE is the same rule.
# A root that is not a plain word is single-quoted (install-lib.sh il_shq).
OURS = re.compile(r"^S=(?:[^ ;']*|'.*')/hooks/codex-dispatch[.]sh; ")
# A table header as TOML allows it: indented, spaced, a comment after it.
SP = r"[ \t]*"


def holds(block, digest):
    """The table's trusted_hash VALUE is the digest; one in a comment is not trust."""
    m = re.search(r'(?m)^[ \t]*trusted_hash[ \t]*=[ \t]*"([^"]*)"', block)
    return bool(m) and m.group(1) == digest


def header(key):
    return r"(?m)^" + SP + r"\[" + SP + "hooks" + SP + r"\." + SP + "state" + SP + r"\." + SP + '"' + re.escape(key) + '"' + SP + r"\]" + SP + r"(?:#[^\n]*)?"


def label(home, event_name, gi, hi, hook):
    return f"{home}: {event_name}[{gi}].hooks[{hi}] ({str(hook.get('command', ''))[:70]})"


def trust_home(home, mode, everything=False):
    """One run at a time per config.toml: launches run this at once, and a lost update drops another run's entries.

    The lock is the folder of the file the link resolves to, so two homes linking one file share it; not the
    file itself, which os.replace swaps for a new one. install-lib.sh il_notify takes the same lock.
    The link is resolved once per pass: every read and write of the pass uses that one name, never the link."""
    link = os.path.join(home, "config.toml")
    while True:
        target = os.path.realpath(link)
        if not os.path.isdir(os.path.dirname(target)):
            return update_home(home, target, mode, everything)
        lock = os.open(os.path.dirname(target), os.O_RDONLY)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
            # The one retry: the link repointed before the lock or during the pass. Start over where it points now.
            if os.path.realpath(link) != target:
                continue
            unwritten = update_home(home, target, mode, everything)
            if os.path.realpath(link) == target:
                return unwritten
        finally:
            os.close(lock)


def update_home(home, config_path, mode, everything):
    hooks_path = os.path.join(home, "hooks.json")
    # A check with no config.toml goes on: no hook in it can be trusted.
    if not os.path.isfile(hooks_path) or (mode not in ("--check", "--list") and not os.path.isfile(config_path)):
        print(f"{home}: no hooks.json or config.toml, skipped")
        return
    hooks = json.load(open(hooks_path)).get("hooks", {})
    # A linked hooks.json is keyed under both its own path and its target.
    paths = [hooks_path]
    real = os.path.realpath(hooks_path)
    if real != hooks_path:
        paths.append(real)

    # Taken before the read, so a change during the read also fails the check before the write.
    seen = os.lstat(config_path) if os.path.isfile(config_path) else None
    config = open(config_path).read() if seen else ""
    # The block pattern below ends every line with a newline; valid TOML need not end with one.
    if config and not config.endswith("\n"):
        config += "\n"
    original = config
    unwritten = []
    for event_name, groups in hooks.items():
        event = EVENTS.get(event_name)
        for gi, group in enumerate(groups):
            for hi, hook in enumerate(group.get("hooks", [])):
                # Codex takes more events than EVENTS lists (SessionEnd)
                # and more handler types than `command` (McpTool,
                # Prompt, Agent). Guessing a label or a matcher rule for one
                # would produce a hash nothing can check, and a WRONG hash reads
                # as success while still opening the review menu -- so an entry
                # this script does not recognise is reported, never guessed.
                kind = hook.get("type", "command")
                if not everything and not OURS.search(str(hook.get("command", ""))):
                    continue
                if event is None or kind != "command":
                    unwritten.append(f"{home}: {event_name}[{gi}].hooks[{hi}] (type {kind})")
                    continue
                if mode == "--list":
                    print(label(home, event_name, gi, hi, hook))
                    continue
                digest = hook_hash(event, hook, group.get("matcher"))
                for path in paths:
                    key = f"{path}:{event}:{gi}:{hi}"
                    block = f'[hooks.state."{key}"]\ntrusted_hash = "{digest}"\n'
                    pattern = re.compile(header(key) + r'\n(?:(?![ \t]*\[)[^\n]*\n)*')
                    match = pattern.search(config)
                    if mode == "--check":
                        if not match or not holds(match.group(0), digest):
                            # A hash that is there but differs is a hook changed since it was trusted.
                            unwritten.append(f"{label(home, event_name, gi, hi, hook)} is {'modified' if match else 'not trusted'}")
                        continue
                    if mode == "--forget":
                        if match:
                            # The blank line this script put before the block goes with it.
                            start = match.start() - (1 if config[: match.start()].endswith("\n\n") else 0)
                            config = config[:start] + config[match.end():]
                            print(f"{home}: forgot {key}")
                        continue
                    if match:
                        old = match.group(0)
                        if holds(old, digest):
                            continue
                        # Rewrite ONLY the hash line. An absent `enabled` means
                        # enabled, so the block a user disabled in /hooks
                        # carries `enabled = false` and replacing the whole
                        # block would silently re-enable that hook.
                        new = re.sub(
                            r'(?m)^[ \t]*trusted_hash[ \t]*=.*$',
                            f'trusted_hash = "{digest}"',
                            old,
                            count=1,
                        )
                        if new == old:
                            head, sep, rest = old.partition("\n")
                            new = f'{head}{sep}trusted_hash = "{digest}"\n{rest}'
                        config = config[: match.start()] + new + config[match.end():]
                        print(f"{home}: rewrote {key}")
                    else:
                        if not config.endswith("\n"):
                            config += "\n"
                        config += "\n" + block
                        print(f"{home}: added {key}")
    if mode == "--forget":
        # Codex keys a hook's state by position. Uninstall takes the plugin's
        # entries out next, and each hook behind one moves up: its state (its
        # trust, an `enabled = false`) moves with it, lowest position first.
        # shortcut: an event EVENTS does not list has no label to rename by; add it there if Codex gains one.
        for event_name, groups in hooks.items():
            event = EVENTS.get(event_name)
            if event is None:
                continue
            gn = 0
            for gi, group in enumerate(groups):
                kept = [hi for hi, h in enumerate(group.get("hooks", [])) if not OURS.search(str(h.get("command", "")))]
                for hn, hi in enumerate(kept):
                    if (gn, hn) != (gi, hi):
                        for path in paths:
                            moved = f'[hooks.state."{path}:{event}:{gn}:{hn}"]'
                            config = re.sub(header(f"{path}:{event}:{gi}:{hi}") + "$", lambda _: moved, config)
                gn += 1 if kept else 0
    if config != original:
        # Codex will not start on a config it cannot parse. A table written a
        # way this script does not edit (dotted keys, an inline table) is left alone.
        try:
            import tomllib
            tomllib.loads(config)
        except ImportError:
            pass
        except ValueError as e:
            unwritten.append(f"{home}: config.toml would not parse after this change ({e}); nothing was written")
            return unwritten
        # Replaced whole, never truncated in place: Codex, or a run not under the lock, reads the old file or the new.
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_path), prefix=".config.toml.")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(config)
            os.chmod(tmp, os.stat(config_path).st_mode & 0o7777)
            # Not the regular file read above (a link now, another file, edited): refuse, and trust_home retries a
            # link at its target. A change between this check and os.replace is still written over: closing that
            # window needs a lock every other writer honours.
            now = os.lstat(config_path) if os.path.lexists(config_path) else None
            if not (seen and now and stat.S_ISREG(now.st_mode) and (now.st_ino, now.st_mtime_ns) == (seen.st_ino, seen.st_mtime_ns)):
                os.unlink(tmp)
                unwritten.append(f"{home}: {config_path} changed since it was read; nothing was written, run this again")
                return unwritten
            os.replace(tmp, config_path)
        except BaseException:
            os.unlink(tmp)
            raise
    elif not mode:
        print(f"{home}: every plugin hook already trusted")
    return unwritten


if __name__ == "__main__":
    args = sys.argv[1:]
    flags = []
    while args and args[0].startswith("--"):
        flags.append(args.pop(0))
    if any(f not in ("--check", "--forget", "--list", "--all") for f in flags):
        sys.exit(__doc__)
    mode = next((f for f in flags if f != "--all"), "")
    # --forget takes out the plugin's entries only: another tool's trust is the owner's.
    everything = "--all" in flags and mode != "--forget"
    homes = args or [os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")]
    skipped = []
    for h in homes:
        skipped += trust_home(os.path.abspath(os.path.expanduser(h)), mode, everything) or []
    if skipped and mode == "--check":
        print("\n".join(skipped), file=sys.stderr)
        sys.exit(1)
    if skipped:
        # Fail loud. A hook left untrusted opens every Codex pane on the "Hooks
        # need review" menu, which `terminal send` cannot answer.
        print("\nNO TRUST ENTRY WRITTEN for:", file=sys.stderr)
        for entry in skipped:
            print(f"  {entry}", file=sys.stderr)
        print("Trust these in the /hooks menu, or teach this script the shape.", file=sys.stderr)
        sys.exit(1)

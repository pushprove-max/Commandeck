#!/usr/bin/env python3
"""What the token totals cannot show: what filled the context, caches that expired, main's share,
what each finding was worth, and what happened to the build after it merged.

Every figure is read from logs. Context sizes are estimates from the logged text: the page prints the
margin against the size the API measured at the peak.
"""
import collections
import glob
import json
import os
import re
import subprocess

from timing import rows_of, ts

CHARS_PER_TOKEN = 3  # code and JSON run denser than the 4 of plain English; checked against logged peaks
IMAGE_TOKENS = 1500
CACHE_TTL_S = 300
GIT_TIMEOUT_S = 10  # collect.py runs inside the merge: a slow git must cost the report a section, never the report
TOP_ITEMS = 12
FINDING_HEAD = r'^\s*(?:[-*]\s*)?\[(P[0-3])\]'  # as builder-codex-pass.sh FINDING: a '-' or '*' bullet, or none
FIXED = ('System prompt', 'Tool definitions')  # sent on every request and kept through a compaction
ATTACHED = {'hook_additional_context': 'Hook output', 'hook_system_message': 'Hook output', 'silent_turn_reminder': 'Hook output',
            'nested_memory': 'Instruction files', 'instructions': 'Instruction files', 'output_style': 'Instruction files',
            'output_style_instructions': 'Instruction files', 'skill_listing': 'Tool and skill lists',
            'agent_listing_delta': 'Tool and skill lists', 'deferred_tools_delta': 'Tool and skill lists',
            'deferred_tools_record': 'Tool and skill lists', 'edited_text_file': 'Files changed under the agent', 'queued_command': 'Prompts and briefs'}


def own_usage(u):
    """One call's usage without the advisor's share: that is priced once, in the advisor's own bucket."""
    return u | {'iterations': [i for i in u.get('iterations') or [] if i.get('type') != 'advisor_message']}


def tokens(text):
    return int(len(text) / CHARS_PER_TOKEN)


def flat(body):
    """(text, images) of a tool result; an image's base64 is not what the model is charged for."""
    if isinstance(body, str):
        return body, 0
    text, images = '', 0
    for b in body if isinstance(body, list) else []:
        if isinstance(b, dict) and b.get('type') == 'image':
            images += 1
        elif isinstance(b, dict):
            text += b.get('text') or ''
    return text, images


def attached_text(a):
    for key in ('content', 'text', 'prompt', 'style'):
        if a.get(key):
            return a[key] if isinstance(a[key], str) else json.dumps(a[key])
    return json.dumps({k: v for k, v in a.items() if k != 'type'})


def request_size(u):
    its = [i for i in u.get('iterations') or [] if i.get('type') == 'message'] or [u]
    return max((i.get('input_tokens') or 0) + (i.get('cache_read_input_tokens') or 0) + (i.get('cache_creation_input_tokens') or 0) for i in its)


def fixed_text(path):
    """(source, name, text) of the system prompt and the tool definitions, cut from the first api-request-shape row
    as raw text: rows_of skips every api-request row unparsed, since they are a third of a long log."""
    for line in open(path, errors='replace'):
        if line.startswith('{"type":"api-request-shape"'):
            # The first unescaped key of each name; keys inside the text are escaped and never match.
            at = {m.group(1): m.span() for m in reversed(list(re.finditer(r'"(system|tools)":', line)))}
            ends = sorted(s for s, _ in at.values()) + [len(line)]
            names = {'system': ('System prompt', 'system prompt'), 'tools': ('Tool definitions', 'tool definitions')}
            return [names[k] + (line[end:ends[ends.index(start) + 1]],) for k, (start, end) in at.items()]
    return []


def walk(path):
    """One session log -> (items, request sizes in order, input-side usage per request)."""
    items, sizes, order, tools, cuts = [], {}, [], {}, []

    def put(source, name, text, images=0):
        size = tokens(text) + images * IMAGE_TOKENS
        if size:
            items.append({'source': source, 'name': name, 'tokens': size, 'from': len(order), 'to': None, 'key': hash(text) if text else None})

    for source, name, text in fixed_text(path):
        put(source, name, text)
    for e in rows_of(path):
        kind, m = e.get('type'), e.get('message') or {}
        c = m.get('content')
        if kind == 'system' and e.get('subtype') == 'compact_boundary':
            cuts.append(len(order))
            for i in items:
                if i['to'] is None and i['source'] not in FIXED:
                    i['to'] = len(order)
        elif kind == 'attachment':
            a = e.get('attachment') or {}
            if a.get('type') in ATTACHED:
                put(ATTACHED[a['type']], a.get('hookName') or a.get('path') or a['type'], attached_text(a))
        elif kind == 'assistant':
            mid = m.get('id')
            if mid not in sizes:
                order.append(mid)
            sizes[mid] = (ts(e['timestamp']), m.get('usage') or {}, m.get('model'))
            for b in c if isinstance(c, list) else []:
                if b.get('type') == 'text':
                    put('Replies', 'reply', b.get('text') or '')
                elif b.get('type') == 'tool_use':
                    i = b.get('input') or {}
                    tools[b.get('id')] = (b.get('name'), str(i.get('file_path') or i.get('description') or i.get('command') or '')[-80:])
                    put('Tool calls written', str(b.get('name')), json.dumps(i))
        elif kind == 'user':
            source = 'Compaction summary' if e.get('isCompactSummary') else 'Prompts and briefs'
            if isinstance(c, str):
                put(source, source.lower(), c)
            for b in c if isinstance(c, list) else []:
                if b.get('type') == 'text':
                    put(source, source.lower(), b.get('text') or '')
                elif b.get('type') == 'tool_result':
                    name, what = tools.get(b.get('tool_use_id'), ('unknown tool', ''))
                    text, images = flat(b.get('content'))
                    source2 = 'File reads' if name == 'Read' else 'Helper reports' if name in ('Agent', 'Task') else f'Results: {name}'
                    put(source2, what or str(name), text, images)
    # The log keeps only a thinking block's signature, but the API re-reads the block on later requests:
    # it is what the request wrote beyond its visible text and tool calls.
    shown = collections.Counter()
    for i in items:
        if i['source'] in ('Replies', 'Tool calls written'):
            shown[i['from']] += i['tokens']
    for n, mid in enumerate(order, 1):
        thought = (sizes[mid][1].get('output_tokens') or 0) - shown[n]
        if thought > 0:
            items.append({'source': 'Thinking', 'name': 'thinking', 'tokens': thought, 'from': n,
                          'to': next((c for c in cuts if c >= n), None), 'key': None})
    return items, [sizes[i] for i in order]


def context_breakdown(paths, price):
    """What filled each session's context: at its fullest, and by what it cost to carry from request to request."""
    by_source, top, repeats = collections.defaultdict(lambda: {'carried': 0, 'usd': 0.0}), [], []
    best = {'peak': 0, 'estimated': 0, 'sources': {}}
    carried_all, input_usd_all, unpriced = 0, 0.0, 0
    for path in paths:
        items, reqs = walk(path)
        if not reqs:
            continue
        ctx = [request_size(r[1]) for r in reqs]
        costs = [price(r[2], own_usage(r[1]) | {'output_tokens': 0}) for r in reqs]
        unpriced += costs.count(None)
        input_usd = sum(c or 0 for c in costs)
        carried, peak_at = sum(ctx), max(range(len(ctx)), key=ctx.__getitem__)
        carried_all, input_usd_all = carried_all + carried, input_usd_all + input_usd
        per_token = input_usd / carried if carried else 0
        at_peak = collections.Counter()
        for i in items:
            end = len(ctx) if i['to'] is None else i['to']
            i['requests'] = max(0, end - i['from'])
            i['carried'] = i['tokens'] * i['requests']
            i['usd'] = i['carried'] * per_token
            # Each session keeps its own rate: sessions on different models do not share one.
            by_source[i['source']]['carried'] += i['carried']
            by_source[i['source']]['usd'] += i['usd']
            if i['from'] <= peak_at < end:
                at_peak[i['source']] += i['tokens']
        if ctx[peak_at] > best['peak']:
            best = {'peak': ctx[peak_at], 'estimated': sum(at_peak.values()), 'sources': at_peak}
        top += [{k: i[k] for k in ('source', 'name', 'tokens', 'requests', 'usd')} for i in items if i['source'] not in FIXED]
        seen = collections.defaultdict(list)
        for i in items:
            if i['key'] is not None and i['tokens'] >= 100 and i['source'] not in FIXED:
                seen[i['key']].append(i)
        # The first copy is the one the agent needed; only the copies after it could go.
        repeats += [{'name': v[0]['name'], 'source': v[0]['source'], 'times': len(v), 'tokens': v[0]['tokens'], 'usd': sum(i['usd'] for i in v[1:])}
                    for v in seen.values() if len(v) > 1]
    if not best['peak']:
        return {}
    sources = [{'source': s, 'at_peak': best['sources'].get(s, 0), 'peak_share': best['sources'].get(s, 0) / best['peak'],
                'carry_share': c['carried'] / carried_all if carried_all else 0, 'usd': c['usd']}
               for s, c in by_source.items()]
    return {'peak': best['peak'], 'estimated_at_peak': best['estimated'], 'margin': abs(best['estimated'] - best['peak']) / best['peak'],
            'input_usd': input_usd_all, 'unpriced': unpriced, 'sources': sorted(sources, key=lambda x: -x['usd']),
            'top': sorted(top, key=lambda x: -x['tokens'])[:TOP_ITEMS], 'repeats': sorted(repeats, key=lambda x: -x['usd'])[:TOP_ITEMS]}


def cache_expiry(sessions, price):
    """Requests that re-wrote a cache a pause let expire, and what that paid over reading it."""
    out = []
    for sess in sessions:
        prev, prev_size, prev_model, lifetime = None, 0, None, CACHE_TTL_S
        marks = [c['end'] for c in sess['compactions']]
        for when, u, model in sorted(sess['usage'].values(), key=lambda r: r[0]):
            written = u.get('cache_creation_input_tokens') or 0
            size = (u.get('cache_read_input_tokens') or 0) + written  # what this request left cached; 0 means nothing could expire
            compacted = prev is not None and any(prev <= t <= when for t in marks)
            # A cache belongs to one model, so a new model's first write is no expiry.
            if written and prev_size and model == prev_model and when - prev >= lifetime and not compacted and written >= prev_size / 2:
                # Both sides drop the iterations, so an advisor's bill is no part of the difference. The write keeps
                # the per-lifetime split, which sets its rate; the read cannot have one.
                wrote = {k: v for k, v in u.items() if k != 'iterations'}
                read_instead = {k: v for k, v in wrote.items() if k != 'cache_creation'} | {
                    'cache_creation_input_tokens': 0, 'cache_read_input_tokens': (u.get('cache_read_input_tokens') or 0) + written}
                paid, instead = price(model, wrote), price(model, read_instead)
                out.append({'t': when, 'gap_s': round(when - prev), 'tokens': written,
                            'usd': None if paid is None or instead is None else round(paid - instead, 4)})
            if written:
                # A pause only expires the cache the last write set: seats write 5-minute or 1-hour entries.
                # Any 5-minute part keeps the short lifetime: that part is what a later re-write would bring back.
                split = u.get('cache_creation') or {}
                long_only = split.get('ephemeral_1h_input_tokens') and not split.get('ephemeral_5m_input_tokens')
                lifetime = 3600 if long_only else CACHE_TTL_S
            prev, prev_size, prev_model = when, size, model
    return {'count': len(out), 'tokens': sum(x['tokens'] for x in out), 'usd': round(sum(x['usd'] or 0 for x in out), 2),
            'unpriced': sum(x['usd'] is None for x in out), 'events': out[:TOP_ITEMS]}


def main_seats(main):
    """The seats that run a build without being it: main's own checkout and the Chief-of-Staff worktree."""
    seats = [('main', main)] if main else []
    cos = os.path.expanduser(f'~/orca/workspaces/{os.path.basename(main)}/Chief-of-Staff') if main else ''
    return seats + ([('Chief of Staff', cos)] if os.path.isdir(cos) else [])


def seat_share(seat_dir, unit, t0, t1, price):
    """One seat's requests during the build, and those that name the unit (itself or in what woke them)."""
    window, named, calls, hits, unpriced = 0.0, 0.0, 0, 0, 0
    for path in glob.glob(glob.escape(seat_dir) + '/*.jsonl'):
        if os.path.getmtime(path) < t0:
            continue
        reqs, woke = {}, ''
        for line in open(path, errors='replace'):
            if '"timestamp"' not in line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            # A finished job or a pane message wakes a seat through a queued notice as often as through a user row.
            if e.get('type') == 'user' or (e.get('attachment') or {}).get('type') == 'queued_command':
                woke = line
            elif e.get('type') == 'assistant' and e.get('timestamp') and t0 <= ts(e['timestamp']) <= t1:
                m = e.get('message') or {}
                was = reqs.get(m.get('id'), (None, None, False))
                reqs[m.get('id')] = (m.get('usage') or {}, m.get('model'), was[2] or unit in line or unit in woke)
        for u, model, hit in reqs.values():
            cost = price(model, u)
            unpriced += cost is None
            window, calls = window + (cost or 0), calls + 1
            if hit:
                named, hits = named + (cost or 0), hits + 1
    return {'window_usd': round(window, 2), 'named_usd': round(named, 2), 'requests': calls, 'named_requests': hits, 'unpriced': unpriced}


def main_share(unit, t0, t1, main, projects, price):
    out = {}
    for seat, path in main_seats(main):
        got = seat_share(projects + re.sub(r'[^A-Za-z0-9]', '-', path), unit, t0, t1, price)
        if got['requests']:
            out[seat] = got
    return out


def finding_rows(passes):
    """Each finding: new, or a repeat of a file or a (class: <tag>) an earlier pass already cited.
    A line is a finding by FINDING_HEAD, the head collect.py counts with, so the two counts cannot differ."""
    rows, cited, classes = [], set(), set()
    for p in passes:
        found = []
        for line in (p.get('message') or '').splitlines():
            head = re.match(FINDING_HEAD, line)
            if head:
                rest = line[head.end():]
                tag = re.search(r'\(class: ([^)]+)\)', rest)
                title, _, tail = re.sub(r'\s*\(class: [^)]+\)\s*', ' ', rest).strip().partition(' -- ')
                where = re.match(r'[^\s:]+', tail.strip())
                found.append((head.group(1), tag and tag.group(1).strip(), title.strip(), where.group(0) if where else ''))
        rows += [{'pass': p['n'], 'kind': p['kind'], 'level': level, 'title': title[:90], 'file': where,
                  'repeat': bool(tag and tag in classes) or bool(where and where in cited)} for level, tag, title, where in found]
        cited |= {f[3] for f in found if f[3]}
        classes |= {f[1] for f in found if f[1]}
    return rows


def rejected_files(evidence):
    """Files the evidence says a finding on was refused or accepted as a known failure: likely not a fix."""
    return {f for line in evidence.splitlines() if re.search(r'(?i)\b(refused|rejected|accepted failure|not a bug|false positive)\b', line)
            for f in re.findall(r'[\w./-]+\.\w+', line)}


def finding_value(passes, evidence=''):
    rows, rejected = finding_rows(passes), rejected_files(evidence)
    for r in rows:
        r['rejected'] = r['file'] in rejected
    by_pass = []
    for p in passes:
        mine = [r for r in rows if r['pass'] == p['n']]
        fresh = [r for r in mine if not r['repeat'] and not r['rejected']]
        cost = p.get('usd')
        by_pass.append({'pass': p['n'], 'kind': p['kind'], 'findings': len(mine), 'fresh': len(fresh), 'usd': cost,
                        'usd_per_fresh': round(cost / len(fresh), 2) if cost and fresh else None})
    return {'findings': rows, 'by_pass': by_pass, 'repeats': sum(r['repeat'] for r in rows), 'rejected': sum(r['rejected'] for r in rows)}


def git(repo, *args):
    return subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, timeout=GIT_TIMEOUT_S).stdout.strip()


def after_merge(unit, main):
    """Later fixes and reverts in the files this unit changed. Empty on the day it merges: re-run collect.py later."""
    if not main:
        return {}
    named = git(main, 'log', '--format=%H %s', '--fixed-strings', f'--grep={unit}', '--', '.', ':(exclude).claude/metrics', ':(exclude).claude/briefs').splitlines()
    # The oldest commit past the unit's plan and ledger rows is the build: a later commit naming the unit can
    # be the very repair this section exists to show.
    built = [x.split(' ', 1)[0] for x in named if not re.match(r'\S+ (docs\(plans\)|plan\(|chore\(metrics\))', x)]
    if not built:
        return {'merged': False}
    first = built[-1]
    # -z: without it git quotes a non-ASCII name, and the pathspec below then matches no file.
    files = sorted(f for f in git(main, 'show', '--format=', '--name-only', '-z', first, '--', '.', ':(exclude).claude/metrics').split('\0') if f)
    later = git(main, 'log', '--format=%h %ct %s', f'{first}..HEAD', '--', *files).splitlines() if files else []
    fixes = [{'sha': x.split(' ', 2)[0], 't': int(x.split(' ', 2)[1]), 'subject': x.split(' ', 2)[2][:100]} for x in later
             if re.match(r'\S+ \d+ (fix|revert)', x, re.I)]
    return {'merged': True, 'commit': first[:10], 'files': len(files), 'later_commits': len(later), 'fix_count': len(fixes), 'fixes': fixes[:TOP_ITEMS]}


def after_merge_safe(unit, main):
    try:
        return after_merge(unit, main)
    except subprocess.TimeoutExpired:
        return {'timed_out': True}

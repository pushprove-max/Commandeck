#!/usr/bin/env python3
"""Call-by-call timing from the logs: every model request, every tool call, every logged hook.

A Claude session log stamps each row, so three clocks can be read off it:
  - a model request runs from the last row before its first block to its last block
    (time on Claude's servers; the client also logs how long each thinking block took);
  - a tool call runs from the arrival of its own block, or the end of the call the pane ran
    before it in the same request unless both only look, to its result row, and the hook rows inside that span
    split it into hooks before, the tool itself, hooks after;
  - Stop hooks log their own durations at each turn end.
Only hooks that print something leave a row, so hook figures are a floor per hook; the
before and after phases are read from row times and are whole.
"""
import json
import re
from datetime import datetime

# The tools that only look: the pane runs two of them side by side.
LOOK_TOOLS = ('Read', 'Glob', 'Grep')

def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()


def rows_of(path):
    for line in open(path, errors='replace'):
        # Claude Code 2.1.300's api-request rows are no request of their own and a third or more of a long log: skipped unparsed.
        if line.startswith('{"type":"api-request'):
            continue
        try:
            yield json.loads(line)
        except ValueError:
            continue


def hook_name(command):
    """The script a hook command runs; an inline command is named by what it talks to."""
    command = command or ''
    scripts = re.findall(r'([\w.-]+\.(?:sh|py|mjs|js))', command)
    if scripts:
        return scripts[-1]
    return 'Orca pane hook (inline)' if 'ORCA_AGENT_HOOK' in command else command.strip()[:40] or 'unnamed hook'


def session_ledger(path):
    """One Claude session log -> its model requests, tool calls, hook runs and the client's own counters."""
    reqs, tools, hooks, counters = {}, {}, [], {}
    recent = []  # the last few row times: a request starts at the latest one not after its first block
    for e in rows_of(path):
        kind = e.get('type')
        if kind == 'cost-state':
            # The client's own running totals; the last row of a session is its final count.
            counters = {'api': (e.get('totalAPIDuration') or 0) / 1000, 'tool': (e.get('totalToolDuration') or 0) / 1000,
                        'wall': (e.get('totalDuration') or 0) / 1000}
            continue
        if not e.get('timestamp'):
            continue
        t = ts(e['timestamp'])
        m = e.get('message') or {}
        blocks = m.get('content') if isinstance(m.get('content'), list) else []
        if kind == 'assistant':
            rid = e.get('requestId') or m.get('id')
            r = reqs.get(rid)
            if r is None:
                # think0: how long the first block thought, when the reply opened with thinking.
                # Then first - start - think0 is the wait before the model began at all.
                opened = bool(blocks) and blocks[0].get('type') == 'thinking'
                r = reqs[rid] = {'start': max((x for x in recent if x <= t), default=t), 'first': t, 'think': 0.0, 'tools': [],
                                 'text': False, 'think0': (e.get('thinkingDurationMs') or 0) / 1000 if opened else None, 'thinks': []}
            r.update(end=t, usage=m.get('usage') or r.get('usage') or {}, model=m.get('model'))
            # An advisor consult runs inside the request that asked for it and is part of its time.
            r['advisor'] = sum(1 for i in r['usage'].get('iterations') or [] if i.get('type') == 'advisor_message')
            r['think'] += (e.get('thinkingDurationMs') or 0) / 1000
            # Each block's thinking ran in the seconds before it: what the build review cuts from it.
            r['thinks'].append((t, (e.get('thinkingDurationMs') or 0) / 1000))
            for b in blocks:
                if b.get('type') == 'text' and b.get('text', '').strip():
                    r['text'] = True
                elif b.get('type') == 'tool_use':
                    i = b.get('input') or {}
                    r['tools'].append(b['id'])
                    tools[b['id']] = {'req': rid, 'name': b.get('name'), 'bg': bool(i.get('run_in_background')),
                                      'desc': str(i.get('description') or i.get('file_path') or i.get('skill') or i.get('pattern') or ''),
                                      'cmd': str(i.get('command') or ''), 'at': t, 'end': None, 'pre_start': None, 'pre_end': None, 'post_start': None,
                                      'timeout': False, 'refused': False}
        elif kind == 'user':
            for b in blocks:
                tool = tools.get(b.get('tool_use_id')) if isinstance(b, dict) and b.get('type') == 'tool_result' else None
                if tool:
                    body = b.get('content')
                    tool['end'] = t
                    tool['refused'] = bool(b.get('is_error')) and 'hook error' in (body if isinstance(body, str) else json.dumps(body))[:200]
                    res = e.get('toolUseResult')
                    tool['timeout'] = isinstance(res, dict) and bool(res.get('timedOutAfterMs'))
        elif kind == 'attachment' and (e.get('attachment') or {}).get('type') == 'hook_success':
            a = e['attachment']
            ms = a.get('durationMs') or 0
            tool = tools.get(a.get('toolUseID'))
            if a.get('hookEvent') != 'Stop':  # Stop hooks are all in stop_hook_summary, silent ones included
                hooks.append({'event': a.get('hookEvent'), 'name': hook_name(a.get('command')), 's': ms / 1000, 't': t})
            if tool and a.get('hookEvent') == 'PreToolUse':
                tool['pre_end'] = max(tool['pre_end'] or 0, t)
                tool['pre_start'] = min(tool['pre_start'] or t, t - ms / 1000)
            elif tool and a.get('hookEvent') == 'PostToolUse':
                tool['post_start'] = min(tool['post_start'] or t, t - ms / 1000)
        elif kind == 'system' and e.get('subtype') == 'stop_hook_summary':
            for h in e.get('hookInfos') or []:
                hooks.append({'event': 'Stop', 'name': hook_name(h.get('command')), 's': (h.get('durationMs') or 0) / 1000, 't': t})
        # Rows written while a request is in flight must not move its start: a message queued for
        # the agent, and the tool record that is stamped with the reply itself.
        if kind in ('user', 'system', 'assistant') or (kind == 'attachment' and (e.get('attachment') or {}).get('type')
                                                       not in ('deferred_tools_record', 'queued_command')):
            recent = (recent + [t])[-8:]

    for key, tool in tools.items():
        # The pane starts a call when its own block arrives, and runs the Edits of one request
        # one after another: a call also waits for every earlier call of its request
        # that ended before its own first hook began. Two look tools are the exception:
        # the pane runs them side by side, so a first hook row after the earlier one's end does
        # not show the later one waited, and it keeps its whole time. So does a call with no
        # hook row: nothing shows it waited. Timed from the request's end instead, each Edit
        # was charged the Edits before it as a wait before its hooks.
        # shortcut: a shell call the pane ran beside another call (8 of 72 shell pairs measured)
        # loses the earlier call's time when its first hook row is late; read the pane's own
        # start time for a call if a log ever carries one.
        seen = tool['pre_start']
        before = reqs[tool['req']]['tools']
        waited = [tools[k]['end'] for k in before[:before.index(key)]
                  if tools[k]['end'] is not None and seen is not None and tools[k]['end'] <= seen
                  and not (tool['name'] in LOOK_TOOLS and tools[k]['name'] in LOOK_TOOLS)]
        tool['start'] = start = max([tool['at'], *waited])
        if tool['end'] is None:
            continue
        end = max(tool['end'], start)
        pre = min(max((tool['pre_end'] or start) - start, 0), end - start)
        post = min(max(end - (tool['post_start'] or end), 0), end - start - pre)
        tool.update(end=end, pre=pre, post=post, run=end - start - pre - post)
    return {'requests': reqs, 'tools': tools, 'hooks': hooks, 'counters': counters}


def codex_commands(path):
    """One Codex session record -> its own commands as (seconds, command, end), read from each one's reported wall time.

    The end is the output row's time, so a cut window can be taken off the span that ran before it.
    """
    calls = []
    asked = {}
    for e in rows_of(path):
        pay = e.get('payload') or {}
        if pay.get('type') == 'custom_tool_call':
            asked[pay.get('call_id')] = str(pay.get('input') or '')
        elif pay.get('type') == 'custom_tool_call_output':
            text = json.dumps(pay.get('output'))[:400]
            wall = re.search(r'Wall time ([\d.]+) seconds', text)
            if wall:
                cmd = re.search(r'cmd:\s*\\?"(.+?)\\?"\s*[,}]', asked.get(pay.get('call_id'), ''))
                calls.append((float(wall.group(1)), (cmd.group(1) if cmd else asked.get(pay.get('call_id'), ''))[:120],
                              ts(e['timestamp']) if e.get('timestamp') else None))
    return calls

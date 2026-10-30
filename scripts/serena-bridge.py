"""serena-bridge.py <address>: a Codex seat's Serena, served by the worktree's shared server.

Codex starts this as its `serena` helper in place of `serena start-mcp-server`
(serena-shared.sh seat-args codex). It passes every message between Codex, on
standard input and output, and the one Serena server serena-shared.sh runs for
the worktree, so the seat starts no Serena and no language server of its own.
It runs on Serena's Python, which carries the MCP library.
When either side closes, or the library hands over an exception instead of a
message, it exits: Codex then shows Serena as gone, not a call that never
returns. A call the server answers wrongly gets an error answer from the
library itself, which the bridge passes on.
"""
import os
import sys

import anyio
from mcp.client.streamable_http import streamable_http_client
from mcp.server.stdio import stdio_server


async def main(url: str) -> None:
    code = 0
    async with stdio_server() as (from_codex, to_codex):
        try:
            with anyio.CancelScope() as leaving:
                # Leaving this block tells the server the session ended; it keeps one per seat until told.
                async with streamable_http_client(url) as (from_serena, to_serena):
                    async with anyio.create_task_group() as tg:

                        async def pass_on(source, sink):
                            nonlocal code
                            try:
                                async for message in source:
                                    # The library hands a failure with no call to answer over as an exception; dropping it would leave the caller waiting.
                                    if isinstance(message, Exception):
                                        raise message
                                    await sink.send(message)
                            except Exception as error:
                                print(f"serena-bridge: {url}: {error}", file=sys.stderr, flush=True)
                                code = 1
                            # The goodbye gets 5 s: a server that never answers it must not hold the seat's failed call.
                            leaving.deadline = anyio.current_time() + 5
                            tg.cancel_scope.cancel()

                        tg.start_soon(pass_on, from_codex, to_serena)
                        tg.start_soon(pass_on, from_serena, to_codex)
        finally:
            # A plain return would wait on the thread that reads standard input, which ends only when Codex does.
            sys.stdout.flush()
            os._exit(code)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: serena-bridge.py <address printed by serena-shared.sh start>")
    anyio.run(main, sys.argv[1])

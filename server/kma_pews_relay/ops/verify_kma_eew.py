"""Verify the public relay's WebSocket handshake and messages."""

import argparse
import asyncio
import json

from websockets.asyncio.client import connect


async def verify_socket(url: str, *, station: bool = False) -> None:
    async with asyncio.timeout(8), connect(url, open_timeout=5) as socket:
        heartbeat = json.loads(await socket.recv())
        if heartbeat["type"] != "heartbeat":
            raise ValueError(f"{url} did not send a heartbeat")
        if station:
            stations = json.loads(await socket.recv())
            if stations["type"] != "initial_stations" or not stations["stations"]:
                raise ValueError(f"{url} did not send its station directory")
        await socket.send("ping")
        while json.loads(await socket.recv())["type"] != "pong":
            pass
        print(f"{url}: WebSocket handshake, heartbeat and pong verified", flush=True)


async def verify(url: str, *, existing: bool) -> None:
    ws = url.replace("https://", "wss://", 1).replace("http://", "ws://", 1)
    if not existing:
        await verify_socket(ws + "/kma-eew")
    await verify_socket(ws + "/kma-station", station=True)
    await verify_socket(ws + "/sasmex-eew")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--existing", action="store_true")
    options = parser.parse_args()
    asyncio.run(verify(options.url.rstrip("/"), existing=options.existing))

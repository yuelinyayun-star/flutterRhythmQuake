#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only probe for kotoho7 Scratch/TurboWarp cloud EEW frames.

This is a diagnostic helper for the Scratch `円の中トリガ` branch.  That branch
does not consume raw cloud packet payloads directly; it consumes the decoded
Scratch EEW state (`0EEW`, `0-1EEW発表中`, `0-2EEW追加情報`,
`ten c:震源距離`).  The most important live cloud value for the first EEW route
is:

    #r:最新クラウド変数[2] = ☁ c2h[11..50]

So this script highlights `☁ c2h[11..50]` and only prints raw `☁ c2b*` packet
fields as "not direct circle input" evidence.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from dataclasses import dataclass
from typing import Any


HOSTS = (
    "wss://clouddata-srev.kothn.net",
    "wss://clouddata.turbowarp.org",
    "wss://clouddata.turbowarp.xyz",
)

PROJECT_IDS = (
    "kotoho7.github.io/srev",
    "kotoho7.github.io/srev/2",
)


def scratch_slice(value: str, start: int, end: int | None = None) -> str:
    """Return Scratch-style 1-based slice; `end` is inclusive."""

    if end is None:
        return value[start - 1 :]
    return value[start - 1 : end]


def _digit_int(value: str) -> int | None:
    return int(value) if value.isdigit() else None


def _digits_float(value: str, scale: float = 1.0, offset: float = 0.0) -> float | None:
    if not value.isdigit():
        return None
    return (int(value) / scale) + offset


def _decode_depth(value: str) -> int | str | None:
    if value == "999":
        return "n/unknown"
    parsed = _digit_int(value)
    return parsed


def _decode_magnitude(value: str) -> float | str | None:
    if value == "99":
        return "n/unknown"
    if len(value) == 2 and value.isdigit():
        return int(value) / 10.0
    return None


def decode_eew_payload_fields(value: str) -> dict[str, Any]:
    """Decode the field layout used by Scratch `EEW %s %s`.

    The labels here follow the confirmed writes in the SB3 procedure:

    - `0EEW[+6] = letters 15..17 / 10 + 86`
    - `0EEW[+7] = letters 18..20 / 10`
    - `0EEW[+8] = letters 21..23` or `n`
    - `0EEW[+9] = letters 24..25 as x.y` or `n`

    Several early/control fields are still shown as raw because the Scratch
    project mixes status/cancel/control semantics there.
    """

    result: dict[str, Any] = {
        "raw": value,
        "raw_length": len(value),
    }
    if len(value) < 30:
        result["decoded"] = "too_short_for_EEW_payload_layout"
        return result

    status = scratch_slice(value, 1, 1)
    lon_raw = scratch_slice(value, 15, 17)
    lat_raw = scratch_slice(value, 18, 20)
    depth_raw = scratch_slice(value, 21, 23)
    mag_raw = scratch_slice(value, 24, 25)
    slot_raw = scratch_slice(value, 30, 30)
    result.update(
        {
            "status_or_report_type_letter_1_raw": status,
            "unknown_control_2_4_raw": scratch_slice(value, 2, 4),
            "time_or_origin_5_14_raw": scratch_slice(value, 5, 14),
            "longitude_15_17_raw": lon_raw,
            "longitude_deg_decoded_as_scratch_0EEW_plus_6": _digits_float(
                lon_raw,
                scale=10.0,
                offset=86.0,
            ),
            "latitude_18_20_raw": lat_raw,
            "latitude_deg_decoded_as_scratch_0EEW_plus_7": _digits_float(
                lat_raw,
                scale=10.0,
            ),
            "depth_21_23_raw": depth_raw,
            "depth_km_decoded_as_scratch_0EEW_plus_8": _decode_depth(depth_raw),
            "magnitude_24_25_raw": mag_raw,
            "magnitude_decoded_as_scratch_0EEW_plus_9": _decode_magnitude(
                mag_raw
            ),
            "max_intensity_or_level_26_raw": scratch_slice(value, 26, 26),
            "event_or_id_27_29_raw": scratch_slice(value, 27, 29),
            "slot_30_raw": slot_raw,
            "slot_offset_14x": (
                _digit_int(slot_raw) * 14
                if _digit_int(slot_raw) is not None
                else None
            ),
            "extra_31_40_raw": scratch_slice(value, 31, 40),
            "circle_depth_gate": (
                "passes_<150km"
                if isinstance(_decode_depth(depth_raw), int)
                and _decode_depth(depth_raw) < 150
                else "blocked_or_unknown"
            ),
        }
    )
    return result


def decode_c2h(value: str) -> dict[str, Any]:
    """Decode the c2h routing that Scratch copies into #r[2] / #r[5]."""

    r2 = scratch_slice(value, 11, 50)
    r5 = scratch_slice(value, 51, 256)
    slot = scratch_slice(r2, 30, 30)
    decoded: dict[str, Any] = {
        "cloud": "☁ c2h",
        "length": len(value),
        "r2_latest_cloud_var_2": r2,
        "r5_prefix_latest_cloud_var_5": r5[:80],
        "circle_input_route": "#r[2] = ☁ c2h[11..50]",
    }
    if len(r2) >= 30:
        decoded.update(
            {
                "readable_eew_payload_from_r2": decode_eew_payload_fields(r2),
            }
        )
    return decoded


def decode_c2b_packet(name: str, value: str) -> dict[str, Any]:
    """Decode raw c2b* packet envelope for inspection only."""

    decoded: dict[str, Any] = {
        "cloud": name,
        "length": len(value),
        "prefix": value[:80],
        "circle_input_route": "raw packet only; do not feed directly to 円の中トリガ",
    }
    if len(value) < 30:
        return decoded

    content = scratch_slice(value, 21)
    decoded.update(
        {
            "seq_1_10": scratch_slice(value, 1, 10),
            "packet_id_11_13": scratch_slice(value, 11, 13),
            "magic_14_20": scratch_slice(value, 14, 20),
            "content_prefix": content[:80],
        }
    )
    if len(content) >= 30:
        decoded.update(
            {
                "readable_packet_content_if_interpreted_as_eew_layout": (
                    decode_eew_payload_fields(content)
                ),
            }
        )
    return decoded


@dataclass(frozen=True)
class ProbeTarget:
    host: str
    project_id: str


async def probe_target(target: ProbeTarget, seconds: float) -> bool:
    try:
        import websockets
    except ImportError as exc:
        raise SystemExit(
            "Missing Python package `websockets`. Install it or run from an "
            "environment where it is already available."
        ) from exc

    print(f"CONNECT host={target.host} project={target.project_id}")
    seen: dict[str, str] = {}

    async with websockets.connect(
        target.host,
        origin="https://kotoho7.github.io",
        ping_interval=None,
        open_timeout=10,
    ) as ws:
        await ws.send(
            json.dumps(
                {
                    "method": "handshake",
                    "project_id": target.project_id,
                    "user": "player0000",
                },
                ensure_ascii=False,
            )
        )
        deadline = time.time() + seconds
        while time.time() < deadline:
            try:
                msg = await asyncio.wait_for(
                    ws.recv(), timeout=max(0.5, deadline - time.time())
                )
            except asyncio.TimeoutError:
                break
            for line in msg.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    print(json.dumps({"raw_line": line[:200]}, ensure_ascii=False))
                    continue
                name = obj.get("name") or obj.get("var") or obj.get("variable")
                if not isinstance(name, str):
                    continue
                value = str(obj.get("value", ""))
                if seen.get(name) == value:
                    continue
                seen[name] = value
                if name == "☁ c2h":
                    print(json.dumps(decode_c2h(value), ensure_ascii=False))
                elif name.startswith("☁ c2b"):
                    print(json.dumps(decode_c2b_packet(name, value), ensure_ascii=False))
                elif name in {"☁ c2u", "☁ url", "☁ open link", "☁ eval"}:
                    print(
                        json.dumps(
                            {"cloud": name, "length": len(value), "value": value[:120]},
                            ensure_ascii=False,
                        )
                    )

    print(json.dumps({"seen_cloud_variables": sorted(seen)}, ensure_ascii=False))
    return True


async def main_async(args: argparse.Namespace) -> int:
    targets = [
        ProbeTarget(host=host, project_id=project_id)
        for project_id in PROJECT_IDS
        for host in HOSTS
    ]
    last_error: Exception | None = None
    for target in targets:
        try:
            await probe_target(target, seconds=args.seconds)
            return 0
        except Exception as exc:  # noqa: BLE001 - keep probing fallback hosts.
            last_error = exc
            print(
                json.dumps(
                    {
                        "failed": {
                            "host": target.host,
                            "project_id": target.project_id,
                            "error": repr(exc),
                        }
                    },
                    ensure_ascii=False,
                ),
                file=sys.stderr,
            )
    if last_error is not None:
        raise last_error
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Probe kotoho7 cloud EEW values used by Scratch 円の中トリガ."
    )
    parser.add_argument(
        "--seconds",
        type=float,
        default=20.0,
        help="Seconds to listen after connecting to the first available host.",
    )
    args = parser.parse_args()
    return asyncio.run(main_async(args))


if __name__ == "__main__":
    raise SystemExit(main())

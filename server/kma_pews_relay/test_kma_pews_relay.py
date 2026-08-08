from __future__ import annotations

import asyncio
import unittest
from datetime import UTC, datetime
from types import MethodType

from kma_pews_relay import (
    Config,
    KmaRelay,
    KmaServerClock,
    Station,
    decode_header,
    decode_raw_levels,
    decode_stations,
    fan_compatible_mmi,
    frame_level_capacity,
)


def pack_station_table(coordinates: list[tuple[int, int]]) -> bytes:
    bits = "".join(f"{lat:010b}{lon:010b}" for lat, lon in coordinates)
    bits += "0" * ((8 - len(bits) % 8) % 8)
    return int(bits, 2).to_bytes(len(bits) // 8, "big")


class KmaPewsDecoderTest(unittest.TestCase):
    def test_clock_accepts_kma_st_value(self) -> None:
        clock = KmaServerClock()

        self.assertTrue(clock.update("1784808238.418", 100.0, 100.2))
        self.assertTrue(clock.is_synced)

    def test_decodes_header_bits(self) -> None:
        event_suffix = 6504
        word = (1 << 31) | (0b10 << 29) | event_suffix
        header = decode_header(word.to_bytes(4, "big"))

        self.assertTrue(header.station_table_changed)
        self.assertEqual(header.phase, 2)
        self.assertEqual(header.event_id, "206504")

    def test_decodes_only_complete_station_coordinates(self) -> None:
        table = pack_station_table([(641, 894), (748, 89), (751, 81)])
        stations = decode_stations(table)

        self.assertEqual(len(stations), 3)
        self.assertEqual((stations[0].latitude, stations[0].longitude), (36.41, 128.94))
        self.assertEqual((stations[1].latitude, stations[1].longitude), (37.48, 130.89))
        self.assertEqual((stations[2].latitude, stations[2].longitude), (37.51, 130.81))

    def test_limits_levels_to_station_count(self) -> None:
        frame = b"\x00\x00\x00\x00" + bytes.fromhex("1cde0000")
        self.assertEqual(decode_raw_levels(frame, 3), [1, 12, 13])

    def test_frame_level_capacity_excludes_header(self) -> None:
        frame = b"\x00\x00\x00\x00" + bytes.fromhex("1cde0000")
        self.assertEqual(frame_level_capacity(frame), 8)

    def test_accept_frame_refreshes_stale_station_table(self) -> None:
        relay = KmaRelay(Config())
        relay.state.stations = [Station(36.41, 128.94)] * 719
        refreshed_stamps: list[str] = []

        async def refresh(self: KmaRelay, stamp: str) -> bool:
            refreshed_stamps.append(stamp)
            self.state.stations = [
                Station(36.41, 128.94),
                Station(37.48, 130.89),
                Station(37.51, 130.81),
            ]
            return True

        relay._refresh_station_table = MethodType(refresh, relay)
        frame = b"\x00\x00\x00\x00" + bytes.fromhex("1cde")
        stamp = datetime(2026, 8, 8, 9, 44, 9, tzinfo=UTC)

        asyncio.run(relay._accept_frame(stamp, frame))

        self.assertEqual(refreshed_stamps, ["20260808094409"])
        self.assertEqual(len(relay.state.stations), 3)
        self.assertEqual(relay.state.latest_raw_mmi, [1, 12, 13])

    def test_fan_compatible_level_order(self) -> None:
        expected = {
            0: -3,
            1: -2,
            12: -1,
            13: 0,
            14: 1,
            15: 2,
            2: 3,
            3: 4,
            4: 5,
            5: 6,
            6: 7,
            7: 8,
            8: 9,
            9: 10,
            10: 11,
            11: 11,
        }
        self.assertEqual(
            {raw: fan_compatible_mmi(raw) for raw in range(16)}, expected
        )

    def test_websocket_data_message_keeps_fan_shape(self) -> None:
        relay = KmaRelay(Config())
        relay.state.latest_data = {
            "timestamp": "2026-07-23 20:20:25",
            "mmi": [-2, -1, 0, 1],
        }
        relay.state.latest_md5 = "example-md5"
        relay.state.latest_raw_mmi = [1, 12, 13, 14]
        relay.state.latest_timestamp_utc = "2026-07-23T11:20:25Z"

        message = relay._data_message("update")

        self.assertEqual(set(message), {"type", "source", "Data", "md5"})
        self.assertEqual(set(message["Data"]), {"timestamp", "mmi"})
        self.assertNotIn("rawMmi", message["Data"])
        self.assertNotIn("timestampUtc", message["Data"])


if __name__ == "__main__":
    unittest.main()

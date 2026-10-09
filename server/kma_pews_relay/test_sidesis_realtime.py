from __future__ import annotations

import copy
import hashlib
import json
import unittest
from pathlib import Path

from kma_pews_relay import Config, KmaRelay

from sidesis_realtime import (
    parse_circle_coordinates,
    parse_sidesis_message,
    parse_socket_io_frame,
    socket_url_with_engine_query,
)


class SidesisRealtimeTest(unittest.TestCase):
    def test_adds_engine_io_query_without_dropping_existing_query(self) -> None:
        url = socket_url_with_engine_query(
            "wss://sidesis.iigea.org/socket.io/?foo=bar"
        )
        self.assertIn("EIO=4", url)
        self.assertIn("transport=websocket", url)
        self.assertIn("foo=bar", url)

    def test_parses_socket_io_event_frame(self) -> None:
        result = parse_socket_io_frame(
            '42["message",{"identifier":"CAP-1","severity":"Severe"}]'
        )
        self.assertIsNotNone(result)
        event_name, data = result
        self.assertEqual(event_name, "message")
        self.assertEqual(data["identifier"], "CAP-1")

    def test_ignores_engine_and_heartbeat_frames(self) -> None:
        self.assertIsNone(parse_socket_io_frame("0{\"sid\":\"x\"}"))
        self.assertEqual(
            parse_socket_io_frame("42[\"new_message\"]"),
            ("new_message", None),
        )

    def test_maps_info_severity_and_keeps_real_fields(self) -> None:
        # Existing protocol unit input, not a captured upstream event.
        data = {
            "title": "Sismo",
            "updated": "2026-10-07T14:00:00Z",
            "identifier": "CAP-1",
            "msgType": "Alert",
            "severity": "Minor",
            "info": [
                {
                    "event": "Sismo Moderado",
                    "description": "Descripción original",
                    "severity": "Moderate",
                }
            ],
        }
        original = copy.deepcopy(data)
        event = parse_sidesis_message("new_message", data)
        self.assertEqual(data, original)
        self.assertEqual(event["id"], "CAP-1")
        self.assertEqual(event["eventId"], "CAP-1")
        self.assertEqual(event["severity"], "Moderate")
        self.assertFalse(event["isWarn"])
        self.assertEqual(event["event"], "Sismo Moderado")
        self.assertEqual(event["epochMs"], 1791381600000)
        self.assertNotIn("lat", event)
        self.assertNotIn("lng", event)

    def test_only_severe_is_official_warning(self) -> None:
        event = parse_sidesis_message(
            "new_message",
            {"id": "CAP-2", "severity": "Severe"},
        )
        self.assertTrue(event["isWarn"])
        self.assertEqual(event["severity"], "Severe")

    def test_heartbeat_or_unknown_event_is_not_an_earthquake_event(self) -> None:
        self.assertIsNone(
            parse_sidesis_message(
                "new_message",
                {
                    "type": "heartbeat",
                    "station_name": "TEST",
                    "station_id": "STA-1",
                },
            )
        )
        self.assertIsNone(parse_sidesis_message("other", {"severity": "Severe"}))

    def test_only_the_real_page_event_name_is_accepted(self) -> None:
        # Names of other transport or DOM paths cannot produce live updates.
        for name in ("message", "simulated_alert", "sidesis_message"):
            self.assertIsNone(parse_sidesis_message(name, {"severity": "Severe"}))

    def test_explicit_simulation_replay_and_heartbeat_are_excluded(self) -> None:
        for data in (
            {"isSimulation": True},
            {"isReplay": True},
            {"type": "heartbeat", "severity": "Severe"},
        ):
            self.assertIsNone(parse_sidesis_message("new_message", data))

    def test_invalid_circle_never_produces_default_coordinates(self) -> None:
        for value in (None, "", " ", "NaN,0", "0,Infinity", "91,0", "0,181", "0", "0,0,0"):
            self.assertIsNone(parse_circle_coordinates(value))

    def test_parses_the_unchanged_archived_circle_string(self) -> None:
        # This is an original CAP snapshot, used ONLY to check the circle text
        # decoder. It is not relabeled as a real Socket.IO packet.
        snapshot = read_original_snapshot()
        circle = snapshot["sasmexCap"]["Data"]["areas"][0]["circles"][0]
        self.assertEqual(
            parse_circle_coordinates(circle["raw"]),
            (circle["latitude"], circle["longitude"]),
        )


def read_original_snapshot() -> dict:
    body = (Path(__file__).parent / "test_fixtures" / "sasmex_snapshot_original.json").read_bytes()
    if hashlib.sha256(body).hexdigest() != "81a7d867e8de1d5cb00cab50a6fcb676e83fc9a1e0f2cf65f767b873612a7aed":
        raise AssertionError("Original snapshot was modified")
    return json.loads(body.decode("utf-8"))


class SasmexRealtimeQueryTest(unittest.IsolatedAsyncioTestCase):
    async def test_query_uses_real_io_cache_and_does_not_return_archived_cap(self) -> None:
        snapshot = read_original_snapshot()
        relay = KmaRelay(Config())
        relay.sasno_realtime.state.latest_event = snapshot["sasnoRealtime"]["Data"]
        relay.sasmex.state.latest_event = snapshot["sasmexCap"]["Data"]

        class QueryConnection:
            remote_address = "local-protocol-test"

            def __init__(self):
                self.sent = []

            async def send(self, message):
                self.sent.append(json.loads(message))

            async def __aiter__(self):
                yield '{"type":"query"}'

        connection = QueryConnection()
        await relay.handle_sasmex_websocket(connection)
        query = next(frame for frame in connection.sent if frame["type"] == "query_response")
        self.assertEqual(query, {"type": "query_response", "source": "sasmex", "Data": None})
        self.assertEqual(relay.sasmex.state.latest_event, snapshot["sasmexCap"]["Data"])


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import asyncio
import json
import unittest
from pathlib import Path

from sasno_realtime import (
    SasnoRealtimeConfig,
    SasnoRealtimeFetched,
    SasnoRealtimeFeed,
    parse_firestore_document,
    parse_sasno_event,
)


def firestore_string(value: str) -> dict[str, str]:
    return {"stringValue": value}


def firestore_int(value: int) -> dict[str, str]:
    return {"integerValue": str(value)}


def firestore_double(value: float) -> dict[str, float]:
    return {"doubleValue": value}


class SasnoRealtimeTest(unittest.TestCase):
    def test_parses_web_app_event_document(self) -> None:
        document = parse_firestore_document(
            {
                "fields": {
                    "SASNOEVENTDATA": {
                        "mapValue": {
                            "fields": {
                                "unix": firestore_int(1791259786),
                                "region": firestore_string(
                                    "Santa María Huazolotitlán, Oax."
                                ),
                                "intensity": firestore_string("Moderado"),
                                "epicenter": {
                                    "mapValue": {
                                        "fields": {
                                            "latitude": firestore_double(16.29569),
                                            "longitude": firestore_double(-97.90988),
                                        }
                                    }
                                },
                                "metadata": {
                                    "mapValue": {
                                        "fields": {
                                            "source": firestore_string("SASNO"),
                                            "version": firestore_string("6.1.0"),
                                        }
                                    }
                                },
                            }
                        }
                    }
                }
            }
        )
        event = parse_sasno_event(document)
        self.assertEqual(event["source"], "sasmex")
        self.assertEqual(event["id"], "1791259786000")
        self.assertEqual(event["eventId"], "1791259786000")
        self.assertEqual(event["epochMs"], 1791259786000)
        self.assertEqual(event["region"], "Santa María Huazolotitlán, Oax.")
        self.assertEqual(event["lat"], 16.29569)
        self.assertEqual(event["lng"], -97.90988)
        self.assertEqual(event["intensidad"], "Moderado")
        self.assertEqual(event["grado"], 2)
        self.assertEqual(event["severidad"], 3)
        self.assertFalse(event["isWarn"])
        self.assertEqual(event["severity"], "Moderate")
        self.assertEqual(event["severityOrigin"], "intensity")
        self.assertNotIn("fuente", event)
        self.assertNotIn("epicenter", event)

    def test_original_october_6_intensity_is_converted_without_changing_source(self) -> None:
        original = json.loads((Path(__file__).resolve().parents[2] /
            "test/fixtures/sasmex_firestore_20261006.original.json").read_text(encoding="utf-8"))
        before = json.dumps(original, ensure_ascii=False, sort_keys=True)
        event = parse_sasno_event(original)
        self.assertEqual(event["severity"], "Minor")
        self.assertEqual(event["severityOrigin"], "intensity")
        self.assertEqual(event["intensidad"], "Leve")
        self.assertEqual(event["grado"], 1)
        self.assertFalse(event["isWarn"])
        self.assertEqual(event["epochMs"], 1791259786000)
        self.assertEqual(event["lat"], original["epicenter"]["latitude"])
        self.assertEqual(event["lng"], original["epicenter"]["longitude"])
        self.assertEqual(event["original"], original)
        self.assertEqual(json.dumps(original, ensure_ascii=False, sort_keys=True), before)

    def test_matches_web_defaults_and_coordinate_filter(self) -> None:
        event = parse_sasno_event(
            {
                "unix": 1791259786,
                "region": "Desconocido",
                "intensity": "Leve",
                "epicenter": {"latitude": 16.0, "longitude": -98.0},
            }
        )
        self.assertEqual(event["id"], "1791259786000")
        self.assertIsNone(event["lat"])
        self.assertIsNone(event["lng"])
        self.assertEqual(event["intensidad"], "Leve")
        self.assertEqual(event["grado"], 1)
        self.assertEqual(event["severidad"], 2)
        self.assertFalse(event["isWarn"])

    def test_preserves_upstream_severity_and_only_severe_is_warning(self) -> None:
        severe = parse_sasno_event(
            {
                "unix": 1791259786,
                "region": "Test",
                "intensity": "Fuerte",
                "severity": "Severe",
            }
        )
        moderate = parse_sasno_event(
            {
                "unix": 1791259786,
                "region": "Test",
                "intensity": "Moderado",
                "severity": "Moderate",
            }
        )

        self.assertEqual(severe["severity"], "Severe")
        self.assertTrue(severe["isWarn"])
        self.assertEqual(moderate["severity"], "Moderate")
        self.assertFalse(moderate["isWarn"])

    def test_first_poll_is_baseline_and_changed_document_is_update(self) -> None:
        updates: list[dict] = []
        bodies = []
        for unix in (1791259786, 1791259786, 1791259846):
            body = {
                "fields": {
                    "SASNOEVENTDATA": {
                        "mapValue": {
                            "fields": {
                                "unix": firestore_int(unix),
                                "region": firestore_string("Test"),
                                "intensity": firestore_string("Leve"),
                            }
                        }
                    }
                }
            }
            bodies.append(
                SasnoRealtimeFetched(
                    url="https://firestore.googleapis.com/test",
                    status=200,
                    body=json.dumps(body).encode("utf-8"),
                    headers={},
                    round_trip_seconds=0.01,
                    received_at_utc="2026-10-07T00:00:00+00:00",
                )
            )

        async def on_update(event: dict) -> None:
            updates.append(event)

        feed = SasnoRealtimeFeed(
            SasnoRealtimeConfig(
                project_id="sasno-d79e1",
                poll_seconds=5,
                timeout_seconds=15,
                stale_after_seconds=30,
            ),
            on_update,
        )

        async def get():
            return bodies.pop(0)

        async def run() -> None:
            feed._get = get  # type: ignore[method-assign]
            self.assertIsNone(await feed.poll_once())
            self.assertIsNone(await feed.poll_once())
            result = await feed.poll_once()
            self.assertIsNotNone(result)

        asyncio.run(run())
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0]["id"], "1791259846000")


if __name__ == "__main__":
    unittest.main()

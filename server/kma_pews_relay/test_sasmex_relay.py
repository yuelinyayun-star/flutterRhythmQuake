from __future__ import annotations

import unittest

from sasmex_relay import parse_alert_summary, parse_cap_xml, to_client_payload


CAP = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <content type="text/xml">
      <alert xmlns="urn:oasis:names:tc:emergency:cap:1.1">
        <identifier>CIRES20260908212605</identifier>
        <sender>cires.org.mx</sender>
        <sent>2026-09-08T21:26:05-06:00</sent>
        <status>Actual</status>
        <msgType>Alert</msgType>
        <scope>Public</scope>
        <info>
          <language>es-MX</language>
          <category>Geo</category>
          <event>SASMEX: Sismo Moderado</event>
          <responseType>Monitor</responseType>
          <urgency>Immediate</urgency>
          <certainty>Observed</certainty>
          <effective>2026-09-08T21:26:05-06:00</effective>
          <expires>2026-09-08T21:27:05-06:00</expires>
          <parameter><valueName>messageIdentifier</valueName><value>4370</value></parameter>
          <area>
            <areaDesc>Zona Probable Epicentro</areaDesc>
            <circle>18.27,-101.89 70.0</circle>
          </area>
        </info>
      </alert>
    </content>
  </entry>
</feed>'''

CAP_WARNING = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <content type="text/xml">
      <alert xmlns="urn:oasis:names:tc:emergency:cap:1.1">
        <identifier>CIRES20260504091933</identifier>
        <sender>cires.org.mx</sender>
        <sent>2026-05-04T09:19:33-06:00</sent>
        <status>Actual</status>
        <msgType>Update</msgType>
        <scope>Public</scope>
        <references>cires.org.mx,CIRES_20260504091932,2026-05-04T09:19:32-06:00</references>
        <info>
          <language>es-MX</language>
          <category>Geo</category>
          <event>SASMEX: ALERTA SISMICA en CDMX por sismo en Costa Oax-Gro</event>
          <responseType>Execute</responseType>
          <urgency>Immediate</urgency>
          <severity>Severe</severity>
          <certainty>Observed</certainty>
          <effective>2026-05-04T09:19:33-06:00</effective>
          <expires>2026-05-04T09:20:33-06:00</expires>
          <headline>ALERTA SISMICA por sismo Severo en Costa Oax-Gro</headline>
          <description>Sismo Severo en Costa Oax-Gro, a 347km de CDMX</description>
          <area>
            <areaDesc>Region de Alertamiento</areaDesc>
            <polygon>15.48,-94.06 18.35,-93.87 18.55,-98.59 15.62,-98.70 15.48,-94.06</polygon>
            <polygon>19.15,-98.95 19.60,-98.95 19.60,-99.35 19.15,-99.35 19.15,-98.95</polygon>
          </area>
        </info>
      </alert>
    </content>
  </entry>
</feed>'''


class SasmexRelayTest(unittest.TestCase):
    def test_summary_normalizes_public_list_fields(self) -> None:
        result = parse_alert_summary(
            {
                "id": "20260908212605",
                "is_event": True,
                "references": [],
                "region": 43208,
                "states": [43],
                "time": "2026-09-08T21:26:05",
            }
        )
        self.assertEqual(result["id"], "20260908212605")
        self.assertTrue(result["isEvent"])
        self.assertEqual(result["states"], [43])

    def test_parses_atom_wrapped_cap_and_circle(self) -> None:
        result = parse_cap_xml(CAP)
        self.assertEqual(result["identifier"], "CIRES20260908212605")
        self.assertEqual(result["msgType"], "Alert")
        self.assertEqual(result["urgency"], "Immediate")
        self.assertEqual(result["eventCodes"], [])
        self.assertEqual(result["parameters"][0]["value"], "4370")
        self.assertEqual(
            result["areas"][0]["circles"][0]["data"],
            {"latitude": 18.27, "longitude": -101.89, "radiusKm": 70.0},
        )

    def test_rejects_cap_without_alert_info(self) -> None:
        with self.assertRaises(ValueError):
            parse_cap_xml("<feed xmlns='http://www.w3.org/2005/Atom'/>")

    def test_monitor_payload_is_compact_and_does_not_invent_fields(self) -> None:
        summary = parse_alert_summary(
            {
                "id": "20260908212605",
                "is_event": True,
                "region": "Guerrero",
                "time": "2026-09-08T21:26:05-06:00",
            }
        )
        payload = to_client_payload(summary, parse_cap_xml(CAP))
        self.assertEqual(payload["eventId"], "20260908212605")
        self.assertFalse(payload["sasmexAlertIssued"])
        self.assertEqual(payload["sasmexAlertAction"], "Monitor")
        self.assertEqual(payload["areas"][0]["circles"][0]["latitude"], 18.27)
        self.assertEqual(payload["areas"][0]["circles"][0]["radiusKm"], 70.0)
        self.assertNotIn("magnitude", payload)
        self.assertNotIn("depth", payload)
        self.assertNotIn("epiIntensity", payload)
        self.assertNotIn("maxIntensity", payload)
        self.assertNotIn("updates", payload)
        self.assertNotIn("rawCapXml", payload)

    def test_execute_payload_is_warning_and_keeps_all_polygons(self) -> None:
        summary = parse_alert_summary(
            {
                "id": "20260504091933",
                "is_event": False,
                "references": [
                    {
                        "id": "20260504091932",
                        "is_event": True,
                    }
                ],
                "region": 42201,
                "states": [40],
                "time": "2026-05-04T09:19:33",
            }
        )
        payload = to_client_payload(summary, parse_cap_xml(CAP_WARNING))
        self.assertTrue(payload["sasmexAlertIssued"])
        self.assertEqual(payload["sasmexAlertAction"], "Execute")
        self.assertEqual(len(payload["areas"][0]["polygons"]), 2)
        self.assertEqual(payload["references"][0]["id"], "20260504091932")


if __name__ == "__main__":
    unittest.main()

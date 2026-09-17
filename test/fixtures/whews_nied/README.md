# WHEWS NIED Capture

Unmodified WebSocket payloads captured on 2026-09-08 after successful official
token verification, from `wss://api.beecld.com/ws/nied`. No credentials included.

- `stations.json`: received at 10:47:17.037634 UTC; 1560 coordinates.
- `observations.json`: received at 10:47:23.899674 UTC; source timestamp
  `2026-09-08 19:47:11` with no offset suffix.

The official API documentation (`https://api.beecld.com/`, NIED station section,
retrieved 2026-09-08) explicitly specifies UTC+8 for this timestamp. Its relation
to the capture's receive time instead resembles UTC+9. The parser tests enforce
the documented contract, not a heuristic correction based on the receive time.
This upstream discrepancy remains unresolved.

Two coastal station coordinates are explicitly verified against NIED's
historical location table, rather than inferred from nearby stations:
https://www.kyoshin.bosai.go.jp/en/stationlocationinfobefore20220201/

- NIG005: 37.9204, 138.4981 (MATSUGASAKI).
- YMG008: 34.0121, 131.4042 (YAMAGUCHI).

Prefecture labels otherwise use the existing `japan_prefectures.geojson`
polygons and local station metadata. All 1560 captured coordinates are covered;
raw coordinates and observation values remain unchanged.

# CWA catalogue source audit

The four live JSON files were saved before parsing on 2026-10-28 UTC.
Original event IDs, timestamps, location strings, coordinates, depths and
magnitudes have not been edited. `manifest.json` records the SHA256 digests.

- `trem_list.original.json`: exact HTTP response bytes from
  `https://api.core.exptech.dev/api/v2/eq/report?limit=25` (25 reports).
- `trem_detail.original.json`: exact HTTP response bytes from
  `/api/v2/eq/report/115000-2026-1028-141923` on the same host.
- `jian_cwalist.original.json`: exact UTF-8 `cwalist_response` frame from
  `wss://api.sismotide.top/all`, requested with `cwalist` after authenticated
  connection (50 reports). No authentication frames or credentials retained.
- `whews_cwa.original.json`: exact UTF-8 frame from the authenticated CWA
  endpoint at `api.beecld.com`. The server returned the older 2026-10-17
  11:13:19 event, not the current 2026-10-28 event.
- `fan_documented.original.json`: the unchanged JSON example block under
  `台湾省气象署地震报告 /cwa` in the previously downloaded 2026-10-21
  FAN Studio WebSocket API documentation. This is a documented example,
  **not a live FAN observation**. Direct and configured-proxy connections to
  `ws.fanstudio.tech` failed TLS with `TLSV1_UNRECOGNIZED_NAME`; the configured
  alternate `ws.fanstudio.hk` reset the connection. No certificate checks
  were disabled and no substitute live response was fabricated.

There are 22 overlapping JIAN/TREM reports. Three of those report pairs have
different hypocentral parameters and must still share the same agency event
identity. Comparisons use normalized internal keys; the source reports stay
unchanged. The 2026-10-17 WHEWS report also exists in both captured lists.

The manual map regression also uses two unchanged HTTP response bodies
captured on 2026-11-23 from `api.core.exptech.dev`:

- `trem_list_20261123.original.json`: `/api/v2/eq/report?limit=25`.
  SHA-256: `d2bfc61e91d0891715d8f98989f3f2a5e93b53bbec332e1fb1fd30a8edbe6d9d`.
- `trem_second_detail_20261123.original.json`:
  `/api/v2/eq/report/115000-2026-1117-222850`.
  SHA-256: `eeb38126cd7d2a8da6b441d93afdf997698f9dddea46b40471a255b8cc4fc168`.

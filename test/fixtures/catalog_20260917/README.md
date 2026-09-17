# Unchanged live catalog captures

Captured locally on 2026-09-17 (Asia/Shanghai), during investigation of duplicate
GA rows and an untranslated GSRAS place name.

- `jian_all.json`: original UTF-8 WebSocket snapshot from
  `wss://api.sismotide.top/all`, captured by `tools/probe_jian_api.dart`.
- `whews_all.json`: original UTF-8 WebSocket snapshot from the authenticated
  `wss://api.beecld.com/ws/all`. Only the data snapshot is retained; no credential,
  authorization URL or authentication response is included.

Files are copied byte-for-byte from the captures. No event timestamps, IDs,
place names, coordinates or intensity values have been adjusted. Tests that
need a current lifecycle use explicitly separate synthetic events.

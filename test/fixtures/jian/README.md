# Jian Project raw captures

Captured using `tools/probe_jian_api.dart`, 2026-09-16 10:01 UTC.
Endpoint: `wss://api.sismotide.top/all`.

- `all.json`: initial full snapshot, exact UTF-8 JSON frame, including U+FF1A
  fullwidth source-key separators. 52 source entries, 46 earthquake entries.
- `jmalist_response.json`: exact response to `jmalist`, 50 entries.

These files have not had event times, magnitudes, coordinates or IDs rewritten.
They are historical captures, not current observations. Synthetic lifecycle
inputs in the test file are explicitly separate from these fixtures.

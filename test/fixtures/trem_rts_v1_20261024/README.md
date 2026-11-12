# TREM public rts.v1 capture, 2026-10-24

Original response-body bytes, with no IDs, timestamps or observations changed:

- `station.original.csv`: `https://static.core-tnn1.exptech.dev/resource/station`
  SHA-256 `255ba25451b0808c9ac6e6cbfff43c312705814384abde85a9e4f6311349ce4d`.
- `rts.original.sse`: `https://api.lb-tpe1.exptech.dev/api/v1/trem/sse?topics=trem.rts.v1&mode=live`
  SHA-256 `e9648d94794010d4bcfeb5d4ade9a3fa14be645ac8ee37211f7dfb2f8568a31e`.
  The capture ends after the first complete RTS event: 121 station entries,
  `ts=1792839551662`. The preceding `info` event is retained.

Official protocol references:

- https://github.com/ExpTechTW/TREM-Lite/blob/main/packages/core/src/features/data/dataHttp.ts
- https://github.com/ExpTechTW/TREM-Lite/blob/main/packages/core/src/features/data/resource.ts
- https://github.com/ExpTechTW/TREM-Lite/blob/main/packages/core/src/features/data/rtsV1.ts

The station response currently declares application/json but contains CSV.
RTS data fields contain base64-encoded gzip JSON. The subscription explicitly
requests live mode so quiet stations continue updating. New station IDs are
hex strings and must be joined to this catalogue rather than the old decimal IDs.
Replay archives retain the CSV as an original string and the decompressed JSON
in its original `stations` / `ts` schema. Missing PGV is not inferred from PGA.

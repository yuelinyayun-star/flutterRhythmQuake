# NIED Station Layer Role Audit

- Schema: `nied_station_layer_role_audit_v1`
- Production behavior changed: `true`
- Current routing rule: `all scan-mapped stations default to jma_s`
- Superseded routing rule: `network contains "kik" => jma_b, otherwise jma_s`
- Limitation: `jma_b` is an auxiliary borehole layer, not default scoring evidence.

## Summary

| Metric | Value |
|---|---:|
| Stations | 1749 |
| Scan-mapped stations | 1630 |
| K-NET stations | 1047 |
| KiK-net stations | 702 |
| Current `jma_s` primary | 1749 |
| Current `jma_b` primary | 0 |
| Scan-mapped `jma_s` primary | 1630 |
| Scan-mapped `jma_b` primary | 0 |
| K-NET-like station codes | 1047 |
| KiK-like station codes | 702 |
| Code/network mismatches | 0 |

## Decision

- The current project does not have an authoritative per-station GIF layer role.
- The superseded implementation treated every `KiK-net` station as `jma_b`, including map display sampling.
- Default real-time shindo input and map station display now read `jma_s` for every scan-mapped station.
- `physicalSensorRole` remains separate from `gifDisplayPrimaryLayer`; `jma_b` is retained for explicit auxiliary borehole diagnostics.

## Follow-up

1. Add explicit station metadata for `gifDisplayPrimaryLayer` instead of deriving it from `network`.
2. Map UI should use display-layer policy; source estimation should use sensor-selection policy.
3. Keep candidate coordinates and source-estimation behavior unchanged until replay metrics pass.

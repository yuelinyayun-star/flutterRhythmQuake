# Source JMA Catalog-Link Triage Packet

- Status: `pass`
- Packets: `3`
- Latest available final catalog year: `2023`
- Target event year: `2026`
- External catalog not yet available: `3`
- Manual-review required: `3`
- Write-link allowed: `0`
- Metric promotion allowed: `0`
- Split assignment allowed: `0`

## Packets

| Case | Planned use | Origin JST | Catalog status | Evidence | Decision |
| --- | --- | --- | --- | --- | --- |
| `20260622_kushiro_offshore_m30_jma` | `candidate_region_residual_positive_guard` | `2026-06-22T16:38:12` | `external_catalog_not_yet_available` | `event_year_2026_after_latest_available_final_catalog_2023` | `external_catalog_not_yet_available_keep_diagnostic_only` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `inland_surrounded_control` | `2026-06-24T13:24:45` | `external_catalog_not_yet_available` | `event_year_2026_after_latest_available_final_catalog_2023` | `external_catalog_not_yet_available_keep_diagnostic_only` |
| `20260625_iwate_offshore_m32_jma` | `candidate_region_local_support_positive_guard` | `2026-06-25T19:21:49` | `external_catalog_not_yet_available` | `event_year_2026_after_latest_available_final_catalog_2023` | `external_catalog_not_yet_available_keep_diagnostic_only` |

## Manual Link Commands

### `20260622_kushiro_offshore_m30_jma`

- Dry-run link command:

```powershell
dart run tools\link_jma_catalog.dart --catalog docs/data/jma_catalogs/<catalog>.json --case test/fixtures/source_estimation\kushiro_offshore_m30_20260622_jma.json
```

- Write-link allowed: `false`

### `20260624_fukushima_aizu_m32_jma_eq5`

- Dry-run link command:

```powershell
dart run tools\link_jma_catalog.dart --catalog docs/data/jma_catalogs/<catalog>.json --case test/fixtures/source_estimation\fukushima_aizu_m32_20260624_jma_eq5.json
```

- Write-link allowed: `false`

### `20260625_iwate_offshore_m32_jma`

- Dry-run link command:

```powershell
dart run tools\link_jma_catalog.dart --catalog docs/data/jma_catalogs/<catalog>.json --case test/fixtures/source_estimation\iwate_offshore_m32_20260625_jma.json
```

- Write-link allowed: `false`

## Decision

- Keep all three cases diagnostic-only until a versioned JMA final catalog or equivalent reviewed source is linked.
- Do not mutate fixtures, assign splits, or promote catalog truth from this packet.
- JMA source/intensity text supplied during capture remains reference metadata, not final catalog truth.

## Validation

- Status: `pass`.
- Violations: none.


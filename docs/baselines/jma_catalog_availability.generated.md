# JMA Catalog Availability

- Status: `pass`
- Availability manifest: `docs/data/jma_catalog_availability.json`
- Readiness report: `.dart_tool/source_estimation_split_assignment_readiness/report.json`
- Readiness status: `pass`
- Availability as of: `2026-06-26`
- Latest official final catalog year: `2023`
- Latest official final catalog period end: `2023-12-31`
- Latest-year evidence checked at: `2026-06-26T06:20:00Z`
- Latest-year evidence source: `https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html`
- Observed missing final-catalog year links: `2024`, `2025`, `2026`
- JMA catalog blockers: `9`
- External catalog not yet available: `9`
- Catalog available but link missing: `0`

## Validation

- Errors: none
- Warnings: none

## Blockers

| Case | Origin JST | Truth source | Catalog linked | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:12` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260624_fukushima_aizu_m32_jma_eq5` | `2026-06-24T13:24:45` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:21:49` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `2026-06-26T23:04:00` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `2026-06-26T23:17:46` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `2026-06-26T22:29:02` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260627_fukushima_aizu_m36_jma_equake17` | `2026-06-27T02:33:00` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `2026-06-27T00:33:00` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |
| `20260628_iwate_offshore_m41_jma` | `2026-06-28T14:39:37` | `jma_source_and_intensity_information` | no | `external_catalog_not_yet_available` | event_year_2026_after_latest_available_final_catalog_2023 |

## Decision

- Recent JMA source-and-intensity cases stay reference-only until a versioned final catalog covers the event year and `tools/link_jma_catalog.dart` links a matching record.
- This report must fail once a blocker is within the available final catalog range but still lacks a linked catalog object.

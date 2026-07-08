# Source Surface-Image-Only Comparison

- Status: `pass`
- Method: `nied_gif_hybrid_v1`
- Surface-only meaning: use `jma_s` pixels for every station, including KiK-net; do not feed `jma_b`.
- Cases run: `18`
- Event cases: `16`
- Median of median-error delta: `0.0 km`
- Median of P90-error delta: `0.0 km`
- Better / equal / worse median-error cases: `0 / 12 / 0`

## Cases

| Case | Type | Current-default median/P90 | Surface-check median/P90 | Delta median/P90 | Current frames | Surface frames |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `20260624_fukushima_aizu_m32_jma_eq5` | `event` | 8.0/16.0 | 8.0/16.0 | 0.0/0.0 | 62 | 62 |
| `20260622_fukushima_offshore_m22_eq4` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260621_fukushima_offshore_m32_eq6` | `event` | 165.0/311.0 | 165.0/311.0 | 0.0/0.0 | 47 | 47 |
| `20260620_ibaraki_offshore_m19_ref` | `event` | 114.5/160.0 | 114.5/160.0 | 0.0/0.0 | 40 | 40 |
| `20260622_iwate_east_offshore_m30_hinet` | `event` | 40.0/51.0 | 40.0/51.0 | 0.0/0.0 | 39 | 39 |
| `20260622_iwate_offshore_m30_eq10` | `event` | 24.0/54.4 | 24.0/54.4 | 0.0/0.0 | 47 | 47 |
| `20260625_iwate_offshore_m32_jma` | `event` | 75.0/76.0 | 75.0/76.0 | 0.0/0.0 | 56 | 56 |
| `20260621_iwate_offshore_m33_eq8` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260620_iwate_offshore_m34_ref` | `event` | 45.5/96.0 | 45.5/96.0 | 0.0/0.0 | 56 | 56 |
| `20260622_kushiro_offshore_m30_jma` | `event` | 26.0/117.4 | 26.0/117.4 | 0.0/0.0 | 44 | 44 |
| `20260620_kyoto_s_m18_d12` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260610_nara_m36` | `event` | 7.0/10.0 | 7.0/10.0 | 0.0/0.0 | 37 | 37 |
| `20260614_quiet_175544` | `noise` | -/- | -/- | -/- | 0 | 0 |
| `quiet_20260625_233535_jst_live` | `noise` | -/- | -/- | -/- | 0 | 0 |
| `20260620_satsuma_m26_d179` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `event` | 18.0/68.0 | 18.0/68.0 | 0.0/0.0 | 80 | 80 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `event` | 15.0/55.0 | 15.0/55.0 | 0.0/0.0 | 42 | 42 |
| `20260622_wakayama_south_m25_hinet` | `event` | 4.0/6.0 | 4.0/6.0 | 0.0/0.0 | 43 | 43 |

## Skipped

| Case/manifest | Reason |
| --- | --- |
| `test/fixtures/source_estimation\noto_m27_20260621_jma_eq5.json` | `manifest_parse_failed` |

## Decision

- This report is a regression check for the current `jma_s` default input.
- The historical `dualLayer` input mode name is retained in JSON for compatibility, but current processing reads `jma_s` as the default shindo input.


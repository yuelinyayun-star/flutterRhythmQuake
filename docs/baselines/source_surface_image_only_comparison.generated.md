# Source Surface-Image-Only Comparison

- Status: `pass`
- Method: `nied_gif_hybrid_v1`
- Surface-only meaning: use `jma_s` pixels for every station, including KiK-net; do not feed `jma_b`.
- Cases run: `27`
- Event cases: `25`
- Median of median-error delta: `0.0 km`
- Median of P90-error delta: `0.0 km`
- Better / equal / worse median-error cases: `0 / 21 / 0`

## Cases

| Case | Type | Current-default median/P90 | Surface-check median/P90 | Delta median/P90 | Current frames | Surface frames |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `20260624_fukushima_aizu_m32_jma_eq5` | `event` | 7.0/10.0 | 7.0/10.0 | 0.0/0.0 | 62 | 62 |
| `20260627_fukushima_aizu_m36_jma_equake17` | `event` | 89.0/115.0 | 89.0/115.0 | 0.0/0.0 | 69 | 69 |
| `20260702_fukushima_aizu_m46_jma_p2p` | `event` | 28.0/28.0 | 28.0/28.0 | 0.0/0.0 | 68 | 68 |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | `event` | 61.0/168.0 | 61.0/168.0 | 0.0/0.0 | 7 | 7 |
| `20260622_fukushima_offshore_m22_eq4` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260621_fukushima_offshore_m32_eq6` | `event` | 141.0/184.4 | 141.0/184.4 | 0.0/0.0 | 47 | 47 |
| `20260620_ibaraki_offshore_m19_ref` | `event` | 110.0/110.0 | 110.0/110.0 | 0.0/0.0 | 40 | 40 |
| `20260622_iwate_east_offshore_m30_hinet` | `event` | 43.0/56.6 | 43.0/56.6 | 0.0/0.0 | 39 | 39 |
| `20260622_iwate_offshore_m30_eq10` | `event` | 27.0/54.0 | 27.0/54.0 | 0.0/0.0 | 47 | 47 |
| `20260625_iwate_offshore_m32_jma` | `event` | 17.0/29.5 | 17.0/29.5 | 0.0/0.0 | 56 | 56 |
| `20260621_iwate_offshore_m33_eq8` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260620_iwate_offshore_m34_ref` | `event` | 43.0/83.0 | 43.0/83.0 | 0.0/0.0 | 56 | 56 |
| `20260628_iwate_offshore_m41_jma` | `event` | 40.0/40.0 | 40.0/40.0 | 0.0/0.0 | 98 | 98 |
| `20260622_kushiro_offshore_m30_jma` | `event` | 17.0/28.0 | 17.0/28.0 | 0.0/0.0 | 44 | 44 |
| `20260620_kyoto_s_m18_d12` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260610_nara_m36` | `event` | 7.0/10.8 | 7.0/10.8 | 0.0/0.0 | 37 | 37 |
| `20260614_quiet_175544` | `noise` | -/- | -/- | -/- | 0 | 0 |
| `quiet_20260625_233535_jst_live` | `noise` | -/- | -/- | -/- | 0 | 0 |
| `20260620_satsuma_m26_d179` | `event` | -/- | -/- | -/- | 0 | 0 |
| `20260702_shizuoka_west_m36_jma_p2p` | `event` | 29.0/36.0 | 29.0/36.0 | 0.0/0.0 | 62 | 62 |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `event` | 74.0/103.0 | 74.0/103.0 | 0.0/0.0 | 80 | 80 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `event` | 13.0/50.1 | 13.0/50.1 | 0.0/0.0 | 42 | 42 |
| `20260622_wakayama_south_m25_hinet` | `event` | 3.0/47.0 | 3.0/47.0 | 0.0/0.0 | 43 | 43 |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `event` | 8.0/11.8 | 8.0/11.8 | 0.0/0.0 | 43 | 43 |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `event` | 13.0/57.0 | 13.0/57.0 | 0.0/0.0 | 44 | 44 |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `event` | 11.0/56.6 | 11.0/56.6 | 0.0/0.0 | 65 | 65 |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `event` | 9.0/16.6 | 9.0/16.6 | 0.0/0.0 | 115 | 115 |

## Skipped

| Case/manifest | Reason |
| --- | --- |
| `test/fixtures/source_estimation\noto_m27_20260621_jma_eq5.json` | `manifest_parse_failed` |

## Decision

- This report is a regression check for the current `jma_s` default input.
- The historical `dualLayer` input mode name is retained in JSON for compatibility, but current processing reads `jma_s` as the default shindo input.


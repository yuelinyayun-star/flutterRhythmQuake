# K-NET Official Search Review

- Query window: `2026/06/20` to `2026/06/29`
- Source page: [https://www.kyoshin.bosai.go.jp/en/eqdownload/](https://www.kyoshin.bosai.go.jp/en/eqdownload/)
- API used: `/en/eqdownload/api/eqsearch/`
- Search mode: `sw-condition=on`, `datakind=all`, `site_method=0`

## Result Summary

- Official strong-motion earthquake rows returned: `8`
- Capture fixtures checked: `20`
- Same-event overlaps confirmed from official CSV waveforms: `2`
- Same-event overlaps still unresolved in this query window: `6`

## Confirmed Overlaps

| Capture case | Official origin JST | Official directory id | Official event id |
| --- | --- | --- | --- |
| `20260624_fukushima_aizu_m32_jma_eq5` | `2026/06/24 13:24:00` | `20260624132400` | `20260624132402` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `2026/06/26 22:29:00` | `20260626222900` | `20260626222847` |

## Unresolved Capture Fixtures

The following provisional overlaps did not produce a matching official strong-motion row in the current query window and remain pending:

- `20260621_iwate_offshore_m33_eq8`
- `20260622_kushiro_offshore_m30_jma`
- `20260625_iwate_offshore_m32_jma`
- `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8`
- `20260627_fukushima_aizu_m36_jma_equake17`
- `20260628_iwate_offshore_m41_jma`

## Decision

- The two confirmed rows are safe to use for official CSV waveform download and feature extraction.
- The six unresolved fixtures stay in the confirmation queue until another authoritative source is found.
- This review is diagnostic-only and does not change source estimation or frozen metrics.

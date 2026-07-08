# K-NET Official Unresolved Queue

- Query window: `2026/06/20` to `2026/06/29`
- Source page: [https://www.kyoshin.bosai.go.jp/en/eqdownload/](https://www.kyoshin.bosai.go.jp/en/eqdownload/)
- Review basis: `docs/baselines/knet_official_search_review.generated.md`

## Unresolved Capture Fixtures

These provisional overlaps did not produce a same-event official strong-motion row in the current query window and remain pending.

| Capture case | Origin JST | Expected region | Status |
| --- | --- | --- | --- |
| `20260621_iwate_offshore_m33_eq8` | `2026/06/21 11:32:12` | `Iwate offshore` | `unresolved_official_row_missing` |
| `20260622_kushiro_offshore_m30_jma` | `2026/06/22 16:38:12` | `Kushiro offshore` | `unresolved_official_row_missing` |
| `20260625_iwate_offshore_m32_jma` | `2026/06/25 19:21:49` | `Iwate offshore` | `unresolved_official_row_missing` |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `2026/06/26 23:17:46` | `Yamanashi east / Fuji Five Lakes` | `unresolved_official_row_missing` |
| `20260627_fukushima_aizu_m36_jma_equake17` | `2026/06/27 02:33:00` | `Fukushima Aizu` | `unresolved_official_row_missing` |
| `20260628_iwate_offshore_m41_jma` | `2026/06/28 14:39:37` | `Iwate offshore` | `unresolved_official_row_missing` |

## Decision

- Two confirmed official CSV pairs already moved forward into alignment.
- These six fixtures stay blocked from official CSV waveform download until another authoritative source or a better same-event match is found.
- This queue is diagnostic-only and does not change source estimation or frozen metrics.

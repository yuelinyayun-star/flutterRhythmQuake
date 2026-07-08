# PLUM Replay Capture Gap Report

- Status: `pass`
- Cases scanned: `7`
- Complete cases: `6`
- Total gap cases: `1`
- Unresolved gap cases: `0`
- Excluded gap cases: `1`
- Unresolved failed GIFs: `0`
- Excluded failed GIFs: `16`
- Total failed GIFs: `16`

## Unresolved Gap Cases

| Case | Origin JST | Repair window | Expected | Downloaded | Failed | Action |
| --- | --- | --- | ---: | ---: | ---: | --- |

## Excluded Gap Cases

| Case | Origin JST | Repair window | Expected | Downloaded | Failed | Decision |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `2026-06-26T23:17:46` | `expired_over_3h` | 302 | 286 | 16 | `capture_gap_exclusion_approved` |

## Decision

- This report does not repair or exclude captures automatically.
- Historical NIED GIF capture repair is only considered within 3 hours after the event JST origin time.
- Gap cases with `expired_over_3h` must stay out of complete replay lead-time metrics until an explicit exclusion decision is recorded or the case is replaced by another complete capture with no missing GIFs.
- Excluded gap cases remain excluded from complete replay metrics; they do not count as complete captures and do not require historical re-download.

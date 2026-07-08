# JMA Reference Capture Association

- Status: `pass`
- Manifest: `docs/data/jma_reference_event_candidates.json`
- Events: `7`
- Pending capture: `2`
- Capture associated: `5`
- Missing local association: `2`
- Local capture candidate matches: `4`
- Local fixture candidate matches: `0`
- Capture directory missing: `0`
- Replay manifest missing: `0`

## Validation

- Errors: none
- Warnings: none

## Cases

| Event | Status | Origin JST | Capture | Replay manifest | Local captures | Local fixtures |
| --- | --- | --- | --- | --- | --- | --- |
| `20260625_iwate_offshore_m46_jma_eqsc9` | `pending_capture_association` | `2026-06-26T01:11:51+09:00` | no | no | `` | `` |
| `20260626_yamanashi_central_west_m26_jma_equake5` | `pending_capture_association` | `2026-06-26T15:41:13+09:00` | no | no | `` | `` |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `capture_associated_pending_final_catalog` | `2026-06-26T23:04:00+09:00` | yes | yes | `tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `` |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `capture_associated_pending_final_catalog` | `2026-06-26T23:17:46+09:00` | yes | yes | `` | `` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `capture_associated_pending_final_catalog` | `2026-06-26T22:29:02+09:00` | yes | yes | `tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `` |
| `20260627_fukushima_aizu_m36_jma_equake17` | `capture_associated_pending_final_catalog` | `2026-06-27T02:33:00+09:00` | yes | yes | `tmp/captures/20260627_fukushima_aizu_m36_jma_equake17` | `` |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `capture_associated_pending_final_catalog` | `2026-06-27T00:33:00+09:00` | yes | yes | `tmp/captures/20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `` |

## Decision

- This report only checks whether a recent JMA reference candidate has a local replay/capture association. It does not promote the candidate into frozen metrics and does not mark final catalog truth.
- Pending candidates with no local matches remain reference-only and must wait for a replay package or a later explicit exclusion.
